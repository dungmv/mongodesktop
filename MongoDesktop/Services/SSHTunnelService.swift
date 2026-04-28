import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

// MARK: - SSHTunnelError

enum SSHTunnelError: LocalizedError {
    case configInvalid(String)
    case connectionFailed(String)
    case authenticationFailed(String)
    case timeout(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .configInvalid(let m):      return "SSH config invalid: \(m)"
        case .connectionFailed(let m):    return "SSH connection failed: \(m)"
        case .authenticationFailed(let m): return "SSH authentication failed: \(m)"
        case .timeout(let m):            return "SSH timed out: \(m)"
        case .launchFailed(let m):       return "Failed to launch SOCKS5: \(m)"
        }
    }
}

// MARK: - SSHTunnelService

actor SSHTunnelService {
    static let shared = SSHTunnelService()
    private init() {}

    private var group: MultiThreadedEventLoopGroup?
    private var sshChannel: Channel?
    private var socksServerChannel: Channel?

    // MARK: - Public API

    func validateKeyAccess(config: SSHTunnelConfig) throws {
        guard config.authMode == .privateKey else { return }
        let rawPath = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return }

        let expandedPath = resolvePath(rawPath)
        if !FileManager.default.fileExists(atPath: expandedPath) {
            throw SSHTunnelError.configInvalid("Private key file not found: \(expandedPath)")
        }
    }

    func startSOCKS5Proxy(config: SSHTunnelConfig) async throws -> Int {
        await stopTunnel()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        do {
            // 1. Connect and Authenticate SSH
            let sshChannel = try await connectSSH(config: config, on: group)
            self.sshChannel = sshChannel

            // 2. Start local SOCKS5 server that bridges to SSH
            let localPort = try await startSocks5Server(sshChannel: sshChannel, on: group)
            return localPort
        } catch {
            await stopTunnel()
            throw error
        }
    }

    func stopTunnel() async {
        try? await socksServerChannel?.close()
        socksServerChannel = nil
        try? await sshChannel?.close()
        sshChannel = nil
        try? await group?.shutdownGracefully()
        group = nil
    }

    // MARK: - Internal Logic

    private func connectSSH(config: SSHTunnelConfig, on group: EventLoopGroup) async throws -> Channel {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                Self.configureSSHClientPipeline(on: channel, config: config)
            }

        do {
            let channel = try await bootstrap.connect(host: config.sshHost, port: config.sshPort).get()
            // Wait for auth success event
            try await channel.pipeline.handler(type: SSHAuthEventTracker.self).get().authenticated.futureResult.get()
            return channel
        } catch {
            throw SSHTunnelError.connectionFailed(error.localizedDescription)
        }
    }

    private func startSocks5Server(sshChannel: Channel, on group: EventLoopGroup) async throws -> Int {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(SOCKS5Handler(sshChannel: sshChannel))
            }

        let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        self.socksServerChannel = serverChannel
        
        return serverChannel.localAddress?.port ?? 0
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst(1)
        }
        return path
    }

    @preconcurrency
    private static func configureSSHClientPipeline(on channel: Channel, config: SSHTunnelConfig) -> EventLoopFuture<Void> {
        let clientConfig = SSHClientConfiguration(
            userAuthDelegate: SSHAuthenticator(config: config),
            serverAuthDelegate: SSHAcceptAllServerDelegate()
        )

        return addSSHClientHandlerPreconcurrency(
            role: .client(clientConfig),
            allocator: channel.allocator,
            to: channel.pipeline
        ).flatMap {
            channel.pipeline.addHandler(SSHAuthEventTracker(eventLoop: channel.eventLoop))
        }
    }

    @preconcurrency
    private static func addSSHClientHandlerPreconcurrency(
        role: SSHConnectionRole,
        allocator: ByteBufferAllocator,
        to pipeline: ChannelPipeline
    ) -> EventLoopFuture<Void> {
        do {
            let handler = NIOSSHHandler(
                role: role,
                allocator: allocator,
                inboundChildChannelInitializer: nil
            )
            try pipeline.syncOperations.addHandler(handler)
            return pipeline.eventLoop.makeSucceededFuture(())
        } catch {
            return pipeline.eventLoop.makeFailedFuture(error)
        }
    }
}

// MARK: - SSH Handlers

private final class SSHAcceptAllServerDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

private final class SSHAuthEventTracker: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let authenticated: EventLoopPromise<Void>

    init(eventLoop: EventLoop) {
        self.authenticated = eventLoop.makePromise(of: Void.self)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            authenticated.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        authenticated.fail(error)
        context.close(promise: nil)
    }
}

private struct SSHAuthenticator: NIOSSHClientUserAuthenticationDelegate {
    let config: SSHTunnelConfig

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch config.authMode {
        case .password:
            if availableMethods.contains(.password) {
                let offer = NIOSSHUserAuthenticationOffer(
                    username: config.sshUser,
                    serviceName: "ssh-connection",
                    offer: .password(.init(password: config.password))
                )
                nextChallengePromise.succeed(offer)
            } else {
                nextChallengePromise.fail(SSHTunnelError.authenticationFailed("Server does not support password authentication"))
            }
        case .privateKey:
            // NIOSSH 0.13.0 has limited support for loading private keys from files.
            // For now, we only support ed25519 if we can find a way to parse it, 
            // but since it's complex to implement a PEM parser here, we'll fail if it's a private key.
            // Note: A future improvement would be to use a library like swift-crypto-ssh or similar.
            nextChallengePromise.fail(SSHTunnelError.configInvalid("Native Private Key loading is not yet implemented in this version. Please use password authentication or wait for an update."))
        }
    }
}

// MARK: - SOCKS5 Handler

private final class SOCKS5Handler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum State { case handshake, request, connected }
    private var state: State = .handshake
    private let sshChannel: Channel
    private var remoteChannel: Channel?

    init(sshChannel: Channel) { self.sshChannel = sshChannel }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)

        switch state {
        case .handshake:
            guard buffer.readInteger(as: UInt8.self) == 0x05 else {
                context.close(promise: nil)
                return
            }
            // Skip methods
            let _ = buffer.readInteger(as: UInt8.self)
            
            var response = context.channel.allocator.buffer(capacity: 2)
            response.writeBytes([0x05, 0x00])
            context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
            state = .request

        case .request:
            guard buffer.readInteger(as: UInt8.self) == 0x05 else { return } // ver
            let cmd = buffer.readInteger(as: UInt8.self)
            _ = buffer.readInteger(as: UInt8.self) // rsv
            let atyp = buffer.readInteger(as: UInt8.self)

            guard cmd == 0x01 else { // Connect only
                context.close(promise: nil)
                return
            }

            var host = ""
            if atyp == 0x01 { // IPv4
                guard let b1 = buffer.readInteger(as: UInt8.self),
                      let b2 = buffer.readInteger(as: UInt8.self),
                      let b3 = buffer.readInteger(as: UInt8.self),
                      let b4 = buffer.readInteger(as: UInt8.self) else { return }
                host = "\(b1).\(b2).\(b3).\(b4)"
            } else if atyp == 0x03 { // Domain
                guard let len = buffer.readInteger(as: UInt8.self),
                      let d = buffer.readString(length: Int(len)) else { return }
                host = d
            } else {
                context.close(promise: nil)
                return
            }
            
            guard let port = buffer.readInteger(as: UInt16.self) else { return }
            
            state = .connected
            let promise = sshChannel.eventLoop.makePromise(of: Channel.self)
            let localChannel = context.channel
            let originatorAddress = context.localAddress!
            
            sshChannel.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { handler in
                handler.createChannel(promise, channelType: .directTCPIP(.init(targetHost: host, targetPort: Int(port), originatorAddress: originatorAddress))) { channel, _ in
                    self.remoteChannel = channel
                    return channel.pipeline.addHandler(SSHToLocalBridge(localChannel: localChannel))
                }
            }
            
            promise.futureResult.whenSuccess { _ in
                var res = localChannel.allocator.buffer(capacity: 10)
                res.writeBytes([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                localChannel.writeAndFlush(res, promise: nil)
            }
            
            promise.futureResult.whenFailure { _ in
                var res = localChannel.allocator.buffer(capacity: 10)
                res.writeBytes([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                localChannel.writeAndFlush(res, promise: nil)
                localChannel.close(promise: nil)
            }
            
        case .connected:
            let sshData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
            remoteChannel?.writeAndFlush(sshData, promise: nil)
        }
    }
}

private final class SSHToLocalBridge: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    private let localChannel: Channel

    init(localChannel: Channel) { self.localChannel = localChannel }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = self.unwrapInboundIn(data)
        if case .byteBuffer(let buffer) = sshData.data {
            localChannel.writeAndFlush(localChannel.allocator.buffer(buffer: buffer), promise: nil)
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        localChannel.close(promise: nil)
    }
}
