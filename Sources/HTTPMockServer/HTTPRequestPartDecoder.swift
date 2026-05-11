//
//
//  Created by Mateusz
//

import NIO
import NIOHTTP1
import Foundation

final class HTTPRequestPartDecoder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPRequest

    /// Tracks current HTTP server state.
    /// Modified only on a single EventLoop, so @unchecked Sendable is safe.
    enum RequestState {
        case ready
        case collecting(HTTPRequestHead, ByteBuffer?)
    }

    private(set) var requestState: RequestState

    let baseURL: URL

    init(baseURL: URL) {
        self.requestState = .ready
        self.baseURL = baseURL
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        assert(context.channel.eventLoop.inEventLoop)
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            switch requestState {
            case .ready:
                requestState = .collecting(head, nil)
            case .collecting:
                assertionFailure("Unexpected state: \(self.requestState)")
            }
        case .body(var chunk):
            switch requestState {
            case .ready:
                assertionFailure("Unexpected state: \(self.requestState)")
            case .collecting(let head, var buffer):
                if buffer != nil {
                    buffer!.writeBuffer(&chunk)
                    requestState = .collecting(head, buffer)
                } else {
                    requestState = .collecting(head, chunk)
                }
            }
        case .end(let tailHeaders):
            assert(tailHeaders == nil, "Tail headers are not supported.")
            switch requestState {
            case .ready:
                assertionFailure("Unexpected state: \(self.requestState)")
            case .collecting(let head, let buffer):
                let body: HTTPBody = buffer.map { HTTPBody(buffer: $0) } ?? .empty
                fireRequestRead(head: head, body: body, context: context)
            }
            requestState = .ready
        }
    }

    private func fireRequestRead(head: HTTPRequestHead, body: HTTPBody, context: ChannelHandlerContext) {
        context.fireChannelRead(wrapInboundOut(HTTPRequest(method: head.method, uri: head.uri, version: head.version, headers: head.headers, body: body, baseURL: baseURL)))
    }
}
