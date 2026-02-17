//
//
//  Created by Mateusz
//

import Foundation
import NIO

public final class MockServer {
    public final class Configuration {
        public var basicStubs: [ServerStub]
        public var logger: Logger?

        public init(basicStubs: [ServerStub] = [], logger: Logger? = PrintLogger()) {
            self.basicStubs = basicStubs
            self.logger = logger
        }
    }

    private lazy var group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public nonisolated(unsafe) static var configuration = Configuration()

    public let host: String
    public let port: Int
    public var stubs: [ServerStub]
    public let unhandledBlock: @Sendable (HTTPRequest) -> Void
    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public init(host: String = "127.0.0.1",
                port: Int = .random(in: 6000...8000),
                stubs: [ServerStub],
                unhandledBlock: @Sendable @escaping (HTTPRequest) -> Void = { print("Unhandled \($0)") }) {
        self.host = host
        self.port = port
        self.stubs = stubs
        self.unhandledBlock = unhandledBlock
    }

    lazy var serverBootstrap: ServerBootstrap = {
        let stubs = self.stubs + Self.configuration.basicStubs
        let baseURL = baseURL
        let unhandledBlock = self.unhandledBlock
        return ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            return channel.pipeline.configureHTTPServerPipeline().flatMap {
                return channel.pipeline.addHandlers([
                    HTTPRequestPartDecoder(baseURL: baseURL),
                    StubHandler(stubs: stubs,
                                logger: Self.configuration.logger,
                                unhandledBlock: unhandledBlock)])
            }
        }
        .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
        .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
        .childChannelOption(.maxMessagesPerRead, value: 16)
        .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }()

    public func start() throws {
        try DispatchQueue(label: "server." + UUID().uuidString).sync { [serverBootstrap] in
            Self.configuration.logger?.log("Starting server at \(host):\(port)")
            _ = try serverBootstrap.bind(host: host, port: port).wait()
        }
    }
    
    public func start() async throws {
        Self.configuration.logger?.log("Starting server at \(host):\(port)")
        _ = try await serverBootstrap.bind(host: host, port: port).get()
    }

    public func stop() throws {
        try group.syncShutdownGracefully()
        Self.configuration.logger?.log("Stoped server at \(host):\(port)")
    }
}
