//
//
//  Created by Mateusz
//

import Foundation
import NIOHTTP1

public struct ResponseError: Encodable, Hashable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

open class ServerStub {
    public enum Response: Hashable {
        case success(responseBody: Data, statusCode: HTTPResponseStatus = .ok, contentType: String = "application/json", headers: [String: String] = [:])
        case failure(statusCode: HTTPResponseStatus, responseError: ResponseError)
        
        public init(catching body: () throws -> Data) {
            do {
                self = .success(responseBody: try body(), statusCode: .ok)
            } catch {
                self = .failure(statusCode: .badRequest, responseError: ResponseError(code: "\((error as NSError).domain)_\((error as NSError).code)", message: String(describing: error)))
            }
        }
        
        public static func success<T: Encodable>(response: T,
                                                 statusCode: HTTPResponseStatus = .ok,
                                                 contentType: String = "application/json",
                                                 headers: [String: String] = [:]) -> Response {
            let data = try! JSONEncoder().encode(response)
            return .success(responseBody: data, statusCode: statusCode, contentType: contentType, headers: headers)
        }
    }
    
    public var matchingRequest: (HTTPRequest) -> Bool
    public var handler: (HTTPRequest) -> Response?
    
    /// Return `nil` response if You don't want to handle the request.
    public init(matchingRequest: @escaping (HTTPRequest) -> Bool, handler: @escaping (HTTPRequest) -> Response?) {
        self.matchingRequest = matchingRequest
        self.handler = handler
    }
}

public extension ServerStub {
    convenience init(matchingRequest: @escaping (HTTPRequest) -> Bool,
                     returningFileAt fileURL: @escaping @autoclosure () -> URL) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: try! Data(contentsOf: fileURL())) })
    }

    convenience init(matchingRequest: @escaping (HTTPRequest) -> Bool,
                     returning data: @escaping @autoclosure () -> Data) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: data()) })
    }

    convenience init(matchingRequest: @escaping (HTTPRequest) -> Bool,
                     returning string: @escaping @autoclosure () -> String) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: Data(string().utf8)) })
    }

    convenience init<T: Encodable>(matchingRequest: @escaping (HTTPRequest) -> Bool,
                                   returning response: @escaping @autoclosure () -> T) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in Response(catching: { try JSONEncoder().encode(response()) }) })
    }

    convenience init(matchingRequest: @escaping (HTTPRequest) -> Bool,
                     failing statusCode: @escaping @autoclosure () -> HTTPResponseStatus,
                     responseError: @escaping @autoclosure () -> ResponseError = ResponseError(code: UUID().uuidString, message: UUID().uuidString)) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .failure(statusCode: statusCode(), responseError: responseError()) })
    }
}

public extension ServerStub {
    convenience init(uri: String,
                     returning string: @escaping @autoclosure () -> String) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in .success(responseBody: Data(string().utf8)) })
    }

    convenience init(uri: String,
                     returning data: @escaping @autoclosure () -> Data) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in .success(responseBody: data()) })
    }

    convenience init<T: Encodable>(uri: String,
                                   returning response: @escaping @autoclosure () -> T,
                                   jsonEncoder: JSONEncoder = .init()) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in Response(catching: { try jsonEncoder.encode(response()) }) })
    }
}
