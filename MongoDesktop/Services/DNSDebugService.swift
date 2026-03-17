import Foundation
import dnssd

enum DNSDebugService {
    struct SRVRecord {
        let priority: UInt16
        let weight: UInt16
        let port: UInt16
        let target: String
    }

    static func debug(uri: String) async -> String {
        var lines: [String] = []
        lines.append("DNS Debug")
        lines.append("Input URI: \(uri)")

        guard let parsedHost = parseHost(from: uri) else {
            lines.append("Error: Cannot parse host from URI.")
            return lines.joined(separator: "\n")
        }

        lines.append("Parsed host: \(parsedHost)")
        let isSRV = uri.lowercased().hasPrefix("mongodb+srv://")
        lines.append("Scheme: \(isSRV ? "mongodb+srv" : "mongodb")")

        if isSRV {
            let srvName = "_mongodb._tcp.\(parsedHost)"
            lines.append("SRV lookup: \(srvName)")
            do {
                let records = try await querySRV(name: srvName)
                if records.isEmpty {
                    lines.append("SRV records: none")
                } else {
                    lines.append("SRV records (\(records.count)):")
                    for record in records {
                        lines.append("- \(record.target):\(record.port) (priority \(record.priority), weight \(record.weight))")
                    }
                }

                for record in records {
                    lines.append("")
                    lines.append("Resolve target: \(record.target)")
                    let (ips, error) = resolveHost(record.target)
                    if ips.isEmpty {
                        lines.append("A/AAAA: none")
                        if let error {
                            lines.append("getaddrinfo error: \(error)")
                        }
                    } else {
                        lines.append("A/AAAA:")
                        for ip in ips {
                            lines.append("- \(ip)")
                        }
                    }
                }
            } catch {
                lines.append("SRV query error: \(error.localizedDescription)")
            }
        } else {
            lines.append("Resolve host: \(parsedHost)")
            let (ips, error) = resolveHost(parsedHost)
            if ips.isEmpty {
                lines.append("A/AAAA: none")
                if let error {
                    lines.append("getaddrinfo error: \(error)")
                }
            } else {
                lines.append("A/AAAA:")
                for ip in ips {
                    lines.append("- \(ip)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func parseHost(from uri: String) -> String? {
        var httpURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if httpURI.hasPrefix("mongodb+srv://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb+srv://".count)
        } else if httpURI.hasPrefix("mongodb://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb://".count)
        }
        guard let components = URLComponents(string: httpURI) else { return nil }
        return components.host
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

    private struct DNSError: LocalizedError {
        let code: DNSServiceErrorType
        var errorDescription: String? {
            "DNSService error: \(code)"
        }
    }
}
