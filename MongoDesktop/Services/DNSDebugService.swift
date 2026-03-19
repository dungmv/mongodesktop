import Foundation
import dnssd

enum DNSDebugService {
    struct SRVRecord {
        let priority: UInt16
        let weight: UInt16
        let port: UInt16
        let target: String
    }

    struct TXTRecord {
        let items: [String: String]
    }

    static func resolveSRVAndTXT(host: String) async -> ([SRVRecord], TXTRecord) {
        let srvName = "_mongodb._tcp.\(host)"
        let records = (try? await querySRV(name: srvName)) ?? []
        let txt = (try? await queryTXT(name: host)) ?? TXTRecord(items: [:])
        return (records, txt)
    }

    private static func querySRV(name: String) async throws -> [SRVRecord] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let context = QueryContext()
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                var serviceRef: DNSServiceRef?
                let queryResult = DNSServiceQueryRecord(
                    &serviceRef,
                    0,
                    0,
                    name,
                    UInt16(kDNSServiceType_SRV),
                    UInt16(kDNSServiceClass_IN),
                    srvQueryCallback,
                    contextPtr
                )

                guard queryResult == kDNSServiceErr_NoError, let ref = serviceRef else {
                    Unmanaged<QueryContext>.fromOpaque(contextPtr).release()
                    continuation.resume(throwing: DNSError(code: queryResult))
                    return
                }

                while !context.done {
                    let processResult = DNSServiceProcessResult(ref)
                    if processResult != kDNSServiceErr_NoError {
                        context.errorCode = processResult
                        break
                    }
                }

                DNSServiceRefDeallocate(ref)
                Unmanaged<QueryContext>.fromOpaque(contextPtr).release()

                if context.errorCode != kDNSServiceErr_NoError {
                    continuation.resume(throwing: DNSError(code: context.errorCode))
                    return
                }

                continuation.resume(returning: context.records)
            }
        }
    }

    private static func queryTXT(name: String) async throws -> TXTRecord {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let context = TXTQueryContext()
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                var serviceRef: DNSServiceRef?
                let queryResult = DNSServiceQueryRecord(
                    &serviceRef,
                    0,
                    0,
                    name,
                    UInt16(kDNSServiceType_TXT),
                    UInt16(kDNSServiceClass_IN),
                    txtQueryCallback,
                    contextPtr
                )

                guard queryResult == kDNSServiceErr_NoError, let ref = serviceRef else {
                    Unmanaged<TXTQueryContext>.fromOpaque(contextPtr).release()
                    continuation.resume(throwing: DNSError(code: queryResult))
                    return
                }

                while !context.done {
                    let processResult = DNSServiceProcessResult(ref)
                    if processResult != kDNSServiceErr_NoError {
                        context.errorCode = processResult
                        break
                    }
                }

                DNSServiceRefDeallocate(ref)
                Unmanaged<TXTQueryContext>.fromOpaque(contextPtr).release()

                if context.errorCode != kDNSServiceErr_NoError {
                    continuation.resume(throwing: DNSError(code: context.errorCode))
                    return
                }

                continuation.resume(returning: TXTRecord(items: context.items))
            }
        }
    }

    private static let srvQueryCallback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, rrtype, _, rdlen, rdata, _, context in
        guard let context else { return }
        let ctx = Unmanaged<QueryContext>.fromOpaque(context).takeUnretainedValue()

        if errorCode != kDNSServiceErr_NoError {
            ctx.errorCode = errorCode
            ctx.done = true
            return
        }

        if rrtype == UInt16(kDNSServiceType_SRV), let rdata, rdlen >= 7 {
            if let record = parseSRVRecord(rdata: rdata, length: Int(rdlen)) {
                ctx.records.append(record)
            }
        }

        if flags & kDNSServiceFlagsMoreComing == 0 {
            ctx.done = true
        }
    }

    private static let txtQueryCallback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, rrtype, _, rdlen, rdata, _, context in
        guard let context else { return }
        let ctx = Unmanaged<TXTQueryContext>.fromOpaque(context).takeUnretainedValue()

        if errorCode != kDNSServiceErr_NoError {
            ctx.errorCode = errorCode
            ctx.done = true
            return
        }

        if rrtype == UInt16(kDNSServiceType_TXT), let rdata, rdlen > 0 {
            let items = parseTXTRecord(rdata: rdata, length: Int(rdlen))
            for (k, v) in items {
                ctx.items[k] = v
            }
        }

        if flags & kDNSServiceFlagsMoreComing == 0 {
            ctx.done = true
        }
    }

    private static func parseSRVRecord(rdata: UnsafeRawPointer, length: Int) -> SRVRecord? {
        let bytes = rdata.bindMemory(to: UInt8.self, capacity: length)
        guard length >= 7 else { return nil }

        let priority = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        let weight = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
        let port = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])

        let nameOffset = 6
        let target = parseDomainName(bytes: bytes.advanced(by: nameOffset), length: length - nameOffset)
        guard !target.isEmpty else { return nil }

        return SRVRecord(priority: priority, weight: weight, port: port, target: target)
    }

    private static func parseTXTRecord(rdata: UnsafeRawPointer, length: Int) -> [String: String] {
        let bytes = rdata.bindMemory(to: UInt8.self, capacity: length)
        var index = 0
        var result: [String: String] = [:]
        while index < length {
            let len = Int(bytes[index])
            index += 1
            if len <= 0 || index + len > length { break }
            let slice = UnsafeBufferPointer(start: bytes.advanced(by: index), count: len)
            let entry = String(bytes: slice, encoding: .utf8) ?? ""
            if let eq = entry.firstIndex(of: "=") {
                let key = String(entry[..<eq])
                let value = String(entry[entry.index(after: eq)...])
                if !key.isEmpty {
                    result[key] = value
                }
            }
            index += len
        }
        return result
    }

    private static func parseDomainName(bytes: UnsafePointer<UInt8>, length: Int) -> String {
        var labels: [String] = []
        var index = 0
        while index < length {
            let labelLen = Int(bytes[index])
            if labelLen == 0 { break }
            let start = index + 1
            let end = start + labelLen
            guard end <= length else { break }
            let labelBytes = UnsafeBufferPointer(start: bytes.advanced(by: start), count: labelLen)
            let label = String(bytes: labelBytes, encoding: .utf8) ?? ""
            labels.append(label)
            index = end
        }
        return labels.joined(separator: ".")
    }

    private static func resolveHost(_ host: String) -> (ips: [String], error: String?) {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var res: UnsafeMutablePointer<addrinfo>?
        let result = getaddrinfo(host, nil, &hints, &res)
        guard result == 0 else {
            return ([], String(cString: gai_strerror(result)))
        }

        var ips: [String] = []
        var ptr = res
        while let info = ptr?.pointee {
            if info.ai_family == AF_INET {
                var addr = info.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: buffer)
                if !ips.contains(ip) { ips.append(ip) }
            } else if info.ai_family == AF_INET6 {
                var addr = info.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                let ip = String(cString: buffer)
                if !ips.contains(ip) { ips.append(ip) }
            }
            ptr = info.ai_next
        }

        freeaddrinfo(res)
        return (ips, nil)
    }

    private final class QueryContext {
        var records: [SRVRecord] = []
        var done: Bool = false
        var errorCode: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError)
    }

    private final class TXTQueryContext {
        var items: [String: String] = [:]
        var done: Bool = false
        var errorCode: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError)
    }

    private struct DNSError: LocalizedError {
        let code: DNSServiceErrorType
        var errorDescription: String? {
            "DNSService error: \(code)"
        }
    }
}
