//
//
//  Created by Mateusz
//

import Foundation
import NIO
import NIOHTTP1
import os

final class StubHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPRequest
    typealias InboundOut = HTTPServerResponsePart
    let logger: @Sendable () -> Logger
    let stubs: [ServerStub]
    let unhandledBlock: @Sendable (HTTPRequest) -> Void

    init(stubs: [ServerStub], logger: @Sendable @escaping () -> Logger, unhandledBlock: @Sendable @escaping (HTTPRequest) -> Void) {
        self.stubs = stubs
        self.logger = logger
        self.unhandledBlock = unhandledBlock
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)
        let channel = context.channel
        for stub in stubs {
            guard stub.matchingRequest(request), let response = stub.handler(request) else {
                continue
            }
            logger().notice("Handling \(String(describing: request), privacy: .private) with \(String(describing: response), privacy: .private)")
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
            case .failure(let statusCode, let body, let headers):
                responseBodyData = body
                status = statusCode
                responseContentType = "application/json"
                headers.forEach {
                    httpHeaders.add(name: $0.key, value: $0.value)
                }
            }
            stub.history.append(response)

            httpHeaders.add(name: "Content-Length", value: "\(responseBodyData.count)")
            httpHeaders.add(name: "Content-Type", value: responseContentType)

            let responseHead = HTTPResponseHead(version: request.version, status: status, headers: httpHeaders)
            context.writeAndFlush(wrapInboundOut(HTTPServerResponsePart.head(responseHead)), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: responseBodyData.count)
            buffer.writeBytes(responseBodyData)
            let body = HTTPServerResponsePart.body(.byteBuffer(buffer))
            context.writeAndFlush(wrapInboundOut(body), promise: nil)

            let endpart = HTTPServerResponsePart.end(nil)
            _ = channel.writeAndFlush(endpart).flatMap {
                channel.close()
            }
            return
        }
        unhandledBlock(request)

        logger().warning("Unsupported handling of \(String(describing: request))")

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
        channel.writeAndFlush(endpart).whenComplete { _ in
            channel.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger().fault("Error caught \(error)")
        context.fireErrorCaught(error)
    }

    func channelRegistered(context: ChannelHandlerContext) {
        logger().debug("Channel registered")
        context.fireChannelRegistered()
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        logger().debug("Channel unregistered")
        context.fireChannelUnregistered()
    }

    func channelActive(context: ChannelHandlerContext) {
        logger().debug("Channel active")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        logger().debug("Channel inactive")
        context.fireChannelInactive()
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        logger().log("Channel readComplete")
        context.fireChannelReadComplete()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        logger().debug("Channel writabilityChanged \(context.channel.isWritable)")
        context.fireChannelWritabilityChanged()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        logger().debug("Channel userInboundEventTriggered \(String(describing: event))")
        context.fireUserInboundEventTriggered(event)
    }
}
