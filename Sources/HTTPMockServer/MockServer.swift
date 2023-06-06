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

    private lazy var group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    public static var configuration = Configuration()

    public let host: String
    public let port: Int
    public var stubs: [ServerStub]
    public let unhandledBlock: (HTTPRequest) -> Void

    public init(host: String = "localhost",
                port: Int = 8888,
                stubs: [ServerStub],
                unhandledBlock: @escaping (HTTPRequest) -> Void = { print("Unhandled \($0)") }) {
        self.host = host
        self.port = port
        self.stubs = stubs
        self.unhandledBlock = unhandledBlock
    }

    lazy var serverBootstrap: ServerBootstrap = {
        let stubs = self.stubs + Self.configuration.basicStubs
        let unhandledBlock = self.unhandledBlock
        return ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelInitializer { channel in
            return channel.pipeline.configureHTTPServerPipeline().flatMap {
                return channel.pipeline.addHandlers([
                    HTTPRequestPartDecoder(),
                    StubHandler(stubs: stubs,
                                logger: Self.configuration.logger,
                                unhandledBlock: unhandledBlock)])
            }
        }
        .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
        .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }()

    public func start() throws {
        try DispatchQueue(label: "server." + UUID().uuidString).sync { [serverBootstrap] in
            Self.configuration.logger?.log("Starting server at \(host):\(port)")
            _ = try serverBootstrap.bind(host: host, port: port).wait()
        }
    }

    public func stop() throws {
        try group.syncShutdownGracefully()
        Self.configuration.logger?.log("Stoped server at \(host):\(port)")
    }
}
