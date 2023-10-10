//
//
//  Created by Mateusz
//

import NIO
import NIOHTTP1
import Foundation

final class HTTPRequestPartDecoder: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPRequest

    /// Tracks current HTTP server state
    enum RequestState {
        /// Waiting for request headers
        case ready
        /// Waiting for the body
        /// This allows for performance optimization incase
        /// a body never comes
        case awaitingBody(HTTPRequestHead)
        // first chunk
        case awaitingEnd(HTTPRequestHead, ByteBuffer)
        /// Collecting streaming body
        case streamingBody(HTTPBody.Stream)
    }

    /// Current HTTP state.
    var requestState: RequestState

    /// Maximum body size allowed per request.
    private let maxBodySize: Int

    let baseURL: URL

    init(maxBodySize: Int = 1_000_000, baseURL: URL) {
        self.maxBodySize = maxBodySize
        self.requestState = .ready
        self.baseURL = baseURL
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        assert(context.channel.eventLoop.inEventLoop)
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            switch requestState {
            case .ready: requestState = .awaitingBody(head)
            default: assertionFailure("Unexpected state: \(self.requestState)")
            }
        case .body(let chunk):
            switch requestState {
            case .ready: assertionFailure("Unexpected state: \(self.requestState)")
            case .awaitingBody(let head):
                requestState = .awaitingEnd(head, chunk)
            case .awaitingEnd(let head, let bodyStart):
                let stream = HTTPBody.Stream(on: context.channel.eventLoop)
                requestState = .streamingBody(stream)
                fireRequestRead(head: head, body: .init(stream: stream), context: context)
                stream.write(.chunk(bodyStart))
                stream.write(.chunk(chunk))
            case .streamingBody(let stream):
                stream.write(.chunk(chunk))
            }
        case .end(let tailHeaders):
            assert(tailHeaders == nil, "Tail headers are not supported.")
            switch requestState {
            case .ready: assertionFailure("Unexpected state: \(self.requestState)")
            case .awaitingBody(let head):
                fireRequestRead(head: head, body: .empty, context: context)
            case .awaitingEnd(let head, let chunk):
                fireRequestRead(head: head, body: .init(buffer: chunk), context: context)
            case .streamingBody(let stream): stream.write(.end)
            }
            requestState = .ready
        }
    }

    private func fireRequestRead(head: HTTPRequestHead, body: HTTPBody, context: ChannelHandlerContext) {
        context.fireChannelRead(wrapInboundOut(HTTPRequest(method: head.method, uri: head.uri, version: head.version, headers: head.headers, body: body, baseURL: baseURL)))
    }
}
