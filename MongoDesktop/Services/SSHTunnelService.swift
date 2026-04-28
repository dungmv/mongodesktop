import Foundation
import Darwin

// MARK: - SSHTunnelError

enum SSHTunnelError: LocalizedError {
    case configInvalid(String)
    case launchFailed(String)
    case processExited(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .configInvalid(let m): return "SSH config invalid: \(m)"
        case .launchFailed(let m):  return "Failed to launch SSH: \(m)"
        case .processExited(let m): return "SSH tunnel error: \(m)"
        case .timeout(let m):       return "SSH tunnel timed out: \(m)"
        }
    }
}

// MARK: - SSHTunnelService

actor SSHTunnelService {
    static let shared = SSHTunnelService()
    private init() {}

    private var tunnelProcess: Process?
    private var tempScriptURL: URL?

    // MARK: - Public API

    /// Validates if the private key path exists and is readable.
    func validateKeyAccess(config: SSHTunnelConfig) throws {
        guard config.authMode == .privateKey else { return }
        let rawPath = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return }

        let expandedPath: String
        if rawPath.hasPrefix("~/") {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
                + rawPath.dropFirst(1)
        } else {
            expandedPath = rawPath
        }

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) {
            throw SSHTunnelError.configInvalid("Private key file not found at: \(expandedPath)")
        }
        if isDir.boolValue {
            throw SSHTunnelError.configInvalid("Private key path is a directory, not a file: \(expandedPath)")
        }
        if !FileManager.default.isReadableFile(atPath: expandedPath) {
            throw SSHTunnelError.configInvalid("Private key file is not readable: \(expandedPath). Check file permissions.")
        }
    }

    /// Starts a SOCKS5 proxy via SSH on a local port.
    /// Returns the local port the proxy is listening on.
    func startSOCKS5Proxy(config: SSHTunnelConfig) async throws -> Int {
        await stopTunnel()

        guard !config.sshHost.isEmpty else { throw SSHTunnelError.configInvalid("SSH host is required.") }
        guard !config.sshUser.isEmpty else { throw SSHTunnelError.configInvalid("SSH username is required.") }

        let localPort = try Self.findFreePort()
        let (process, scriptURL) = try buildProcess(
            config: config,
            localPort: localPort
        )
        tempScriptURL = scriptURL

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do { try process.run() }
        catch { throw SSHTunnelError.launchFailed(error.localizedDescription) }

        // Poll until the SOCKS5 port is reachable
        let ready = await Self.pollReady(port: localPort, process: process, timeout: 15)

        guard process.isRunning else {
            let msg = String(
                data: stderrPipe.fileHandleForReading.availableData,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SSHTunnelError.processExited(msg.isEmpty ? "SSH process exited unexpectedly." : msg)
        }
        guard ready else {
            process.terminate()
            throw SSHTunnelError.timeout("SOCKS5 proxy not ready after 15 seconds.")
        }

        tunnelProcess = process
        return localPort
    }

    func stopTunnel() async {
        tunnelProcess?.terminate()
        tunnelProcess = nil
        if let url = tempScriptURL {
            try? FileManager.default.removeItem(at: url)
            tempScriptURL = nil
        }
    }

    // MARK: - Build Process

    private func buildProcess(
        config: SSHTunnelConfig,
        localPort: Int
    ) throws -> (Process, URL?) {

        var args: [String] = [
            "-N",
            "-4",                                   // Force IPv4 only
            "-D", "127.0.0.1:\(localPort)",         // SOCKS5 Dynamic Forwarding
            "-p", String(config.sshPort),
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",   // avoids sandbox write to ~/.ssh/known_hosts
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ConnectTimeout=15",
            "-o", "BatchMode=no",
            "-v",                                   // verbose: stderr shows auth progress
        ]

        var env = ProcessInfo.processInfo.environment
        var scriptURL: URL? = nil

        switch config.authMode {
        case .privateKey:
            let rawPath = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawPath.isEmpty {
                if let agentSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                    env["SSH_AUTH_SOCK"] = agentSock
                }
            } else {
                let expandedPath: String
                if rawPath.hasPrefix("~/") {
                    expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
                        + rawPath.dropFirst(1)
                } else {
                    expandedPath = rawPath
                }
                args += ["-o", "IdentitiesOnly=yes", "-i", expandedPath]
                if !config.privateKeyPassphrase.isEmpty {
                    let url = try writeAskPass(config.privateKeyPassphrase)
                    scriptURL = url
                    env["SSH_ASKPASS"] = url.path
                    env["SSH_ASKPASS_REQUIRE"] = "force"
                    env.removeValue(forKey: "DISPLAY")
                }
            }

        case .password:
            guard !config.password.isEmpty else {
                throw SSHTunnelError.configInvalid("SSH password is required.")
            }
            let url = try writeAskPass(config.password)
            scriptURL = url
            env["SSH_ASKPASS"] = url.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env.removeValue(forKey: "DISPLAY")
            args += ["-o", "PreferredAuthentications=password"]
        }

        args.append("\(config.sshUser)@\(config.sshHost)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.environment = env
        return (process, scriptURL)
    }

    private func writeAskPass(_ text: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("ssh-askpass-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        echo "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
        """
        try script.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.path)
        return fileURL
    }

    // MARK: - Helpers

    private static func pollReady(port: Int, process: Process, timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout && process.isRunning {
            if canTCPConnect(port: port) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }

    private static func canTCPConnect(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func findFreePort() throws -> Int {
        for _ in 0..<20 {
            let port = Int.random(in: 49152...65534)
            if !Self.canTCPConnect(port: port) { return port }
        }
        throw SSHTunnelError.configInvalid("No free local port found after 20 attempts.")
    }
}
