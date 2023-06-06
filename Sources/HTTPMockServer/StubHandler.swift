//
//
//  Created by Mateusz
//

import Foundation
import NIO
import NIOHTTP1

final class StubHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPRequest
    typealias InboundOut = HTTPServerResponsePart
    let logger: Logger?
    let stubs: [ServerStub]
    let unhandledBlock: (HTTPRequest) -> Void

    init(stubs: [ServerStub], logger: Logger?, unhandledBlock: @escaping (HTTPRequest) -> Void) {
        self.stubs = stubs
        self.logger = logger
        self.unhandledBlock = unhandledBlock
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)
        for stub in stubs {
            guard stub.matchingRequest(request), let response = stub.handler(request) else {
                continue
            }
            logger?.log("Handling \(request) with \(response)")
            let responseBodyData: Data
            let status: HTTPResponseStatus
            let responseContentType: String
            var httpHeaders = HTTPHeaders()

            switch response {
            case .success(let responseBody, let statusCode, let contentType, let headers):
                responseBodyData = responseBody
                status = statusCode
                headers.forEach {
                    httpHeaders.add(name: $0.key, value: $0.value)
                }
                responseContentType = contentType
            case .failure(let statusCode, let error):
                responseBodyData = try! JSONEncoder().encode(error)
                status = statusCode
                responseContentType = "application/json"
            }

            httpHeaders.add(name: "Content-Length", value: "\(responseBodyData.count)")
            httpHeaders.add(name: "Content-Type", value: responseContentType)

            let responseHead = HTTPResponseHead(version: request.version, status: status, headers: httpHeaders)
            context.writeAndFlush(wrapInboundOut(HTTPServerResponsePart.head(responseHead)), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: responseBodyData.count)
            buffer.writeBytes(responseBodyData)
            let body = HTTPServerResponsePart.body(.byteBuffer(buffer))
            context.writeAndFlush(wrapInboundOut(body), promise: nil)

            let endpart = HTTPServerResponsePart.end(nil)
            _ = context.channel.writeAndFlush(endpart).flatMap {
                context.channel.close()
            }
            return
        }
        unhandledBlock(request)

        logger?.log("Unsupported handling of \(request)")

        let responseBodyData = try! JSONEncoder().encode(ResponseError(code: "Not found", message: "Not found service for \(request)"))
        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Content-Length", value: "\(responseBodyData.count)")
        httpHeaders.add(name: "Content-Type", value: "application/json")
        let responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .notFound, headers: httpHeaders)
        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: responseBodyData.count)
        buffer.writeBytes(responseBodyData)
        let body = HTTPServerResponsePart.body(.byteBuffer(buffer))
        context.writeAndFlush(wrapInboundOut(body), promise: nil)
         let endpart = HTTPServerResponsePart.end(nil)
        _ = context.channel.writeAndFlush(endpart).flatMap {
            context.channel.close()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger?.log("Error caught \(error)")
        context.fireErrorCaught(error)
    }

    func channelRegistered(context: ChannelHandlerContext) {
        logger?.log("Channel registered")
        context.fireChannelRegistered()
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        logger?.log("Channel unregistered")
        context.fireChannelUnregistered()
    }

    func channelActive(context: ChannelHandlerContext) {
        logger?.log("Channel active")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        logger?.log("Channel inactive")
        context.fireChannelInactive()
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        logger?.log("Channel readComplete")
        context.fireChannelReadComplete()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        logger?.log("Channel writabilityChanged \(context.channel.isWritable)")
        context.fireChannelWritabilityChanged()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        logger?.log("Channel userInboundEventTriggered \(event)")
        context.fireUserInboundEventTriggered(event)
    }
}
