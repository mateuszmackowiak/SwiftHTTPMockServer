//
//
//  Created by Mateusz
//

import Foundation
import NIO
import os

public final class MockServer: @unchecked Sendable {
    public final class Configuration: @unchecked Sendable {
        public var basicStubs: [ServerStub]
        public var logger: Logger

        public init(basicStubs: [ServerStub] = [], logger: Logger) {
            self.basicStubs = basicStubs
            self.logger = logger
        }
    }

    public nonisolated(unsafe) static var configuration = Configuration(logger: Logger(subsystem: "com.mat.logger", category: "MockServer"))

    public let host: String
    public private(set) var port: Int
    public var stubs: [ServerStub]
    public let unhandledBlock: @Sendable (HTTPRequest) -> Void
    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    private let stateLock = NSLock()
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(host: String = "127.0.0.1",
                port: Int = .random(in: 6000...8000),
                stubs: [ServerStub],
                unhandledBlock: @Sendable @escaping (HTTPRequest) -> Void = { _ in }) {
        self.host = host
        self.port = port
        self.stubs = stubs
        self.unhandledBlock = unhandledBlock
    }

    private func makeBootstrap(group: MultiThreadedEventLoopGroup) -> ServerBootstrap {
        let stubs = self.stubs + Self.configuration.basicStubs
        let baseURL = baseURL
        let unhandledBlock = self.unhandledBlock
        return ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandlers([
                        HTTPRequestPartDecoder(baseURL: baseURL),
                        StubHandler(stubs: stubs,
                                    logger: { Self.configuration.logger },
                                    unhandledBlock: unhandledBlock)
                    ])
                }
            }
            .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }

    private static let bindRetryAttempts = 8

    public func start() throws {
        stateLock.withLock {
            precondition(channel == nil, "MockServer already started")
        }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var lastError: Error?
        for attempt in 0...Self.bindRetryAttempts {
            Self.configuration.logger.log("Starting server at \(self.baseURL)")
            do {
                let channel = try makeBootstrap(group: group).bind(host: host, port: port).wait()
                stateLock.withLock {
                    if let actualPort = channel.localAddress?.port { self.port = actualPort }
                    self.group = group
                    self.channel = channel
                }
                return
            } catch {
                lastError = error
                if attempt < Self.bindRetryAttempts {
                    self.port = .random(in: 6000...8000)
                }
            }
        }
        try? group.syncShutdownGracefully()
        throw lastError ?? NSError(domain: "MockServer", code: -1)
    }

    public func start() async throws {
        stateLock.withLock {
            precondition(channel == nil, "MockServer already started")
        }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var lastError: Error?
        for attempt in 0...Self.bindRetryAttempts {
            Self.configuration.logger.log("Starting server at \(self.baseURL)")
            do {
                let channel = try await makeBootstrap(group: group).bind(host: host, port: port).get()
                stateLock.withLock {
                    if let actualPort = channel.localAddress?.port { self.port = actualPort }
                    self.group = group
                    self.channel = channel
                }
                return
            } catch {
                lastError = error
                if attempt < Self.bindRetryAttempts {
                    self.port = .random(in: 6000...8000)
                }
            }
        }
        try? await group.shutdownGracefully()
        throw lastError ?? NSError(domain: "MockServer", code: -1)
    }

    public func stop() throws {
        let (channel, group): (Channel?, MultiThreadedEventLoopGroup?) = stateLock.withLock {
            let c = self.channel
            let g = self.group
            self.channel = nil
            self.group = nil
            return (c, g)
        }
        guard let group = group else { return }
        try? channel?.close().wait()
        try group.syncShutdownGracefully()
        Self.configuration.logger.log("Stopped server at \(self.baseURL)")
    }

    deinit {
        let (channel, group): (Channel?, MultiThreadedEventLoopGroup?) = stateLock.withLock {
            let c = self.channel
            let g = self.group
            self.channel = nil
            self.group = nil
            return (c, g)
        }
        try? channel?.close().wait()
        try? group?.syncShutdownGracefully()
    }
}
