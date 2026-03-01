//
//
//  Created by Mateusz
//

import Foundation
import NIOHTTP1

public struct ResponseError: Codable, Hashable, Sendable {
    public let code: String?
    public let message: String

    public init(code: String? = nil, message: String) {
        self.code = code
        self.message = message
    }
}

open class ServerStub: @unchecked Sendable {
    internal var history = [Response]()
    
    public var responseHistory: [Response] {
        history
    }

    public enum Response: Hashable, Sendable {
        case success(responseBody: Data, statusCode: HTTPResponseStatus = .ok, contentType: String = "application/json", headers: [String: String] = [:])
        case failure(statusCode: HTTPResponseStatus, responseBody: Data, headers: [String: String] = [:])


        
        public init(catching body: () throws -> Data) {
            do {
                self = .success(responseBody: try body(), statusCode: .ok)
            } catch {
                self = .failure(statusCode: .badRequest, response: ResponseError(code: "\((error as NSError).domain)_\((error as NSError).code)", message: String(describing: error)))
            }
        }
        
        public static func success<T: Encodable>(response: T,
                                                 statusCode: HTTPResponseStatus = .ok,
                                                 contentType: String = "application/json",
                                                 headers: [String: String] = [:]) -> Response {
            let data = try! JSONEncoder().encode(response)
            return .success(responseBody: data, statusCode: statusCode, contentType: contentType, headers: headers)
        }

        public static func failure<T: Encodable>(statusCode: HTTPResponseStatus,
                                                 response: T,
                                                 headers: [String: String] = [:]) -> Response {
            let data = try! JSONEncoder().encode(response)
            return .failure(statusCode: statusCode, responseBody: data, headers: headers)
        }

        public static func failure(statusCode: HTTPResponseStatus, responseError: ResponseError, headers: [String: String] = [:]) -> Response {
            .failure(statusCode: statusCode, response: responseError, headers: headers)
        }
    }
    
    public var matchingRequest: @Sendable (HTTPRequest) -> Bool
    public var handler: @Sendable (HTTPRequest) -> Response?
    
    /// Return `nil` response if You don't want to handle the request. 
    public init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool, handler: @Sendable @escaping (HTTPRequest) -> Response?) {
        self.matchingRequest = matchingRequest
        self.handler = handler
    }
}

public extension ServerStub {
    convenience init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                     returningFileAt fileURL: @Sendable @escaping @autoclosure () -> URL) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: try! Data(contentsOf: fileURL())) })
    }

    convenience init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                     returning data: @Sendable @escaping @autoclosure () -> Data) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: data()) })
    }

    convenience init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                     returning string: @Sendable @escaping @autoclosure () -> String) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .success(responseBody: Data(string().utf8)) })
    }

    convenience init<T: Encodable>(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                                   returning response: @Sendable @escaping @autoclosure () -> T) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in Response(catching: { try JSONEncoder().encode(response()) }) })
    }

    convenience init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                     statusCode: @Sendable @escaping @autoclosure () -> HTTPResponseStatus,
                     responseError: @Sendable @escaping @autoclosure () -> ResponseError = ResponseError(code: UUID().uuidString, message: UUID().uuidString)) {
        self.init(matchingRequest: matchingRequest,
                  handler: { _ in .failure(statusCode: statusCode(), response: responseError()) })
    }
}

public extension ServerStub {
    convenience init(uri: String,
                     returning string: @Sendable @escaping @autoclosure () -> String) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in .success(responseBody: Data(string().utf8)) })
    }

    convenience init(uri: String,
                     returning data: @Sendable @escaping @autoclosure () -> Data) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in .success(responseBody: data()) })
    }

    convenience init<T: Encodable>(uri: String,
                                   returning response: @Sendable @escaping () -> T,
                                   jsonEncoder: JSONEncoder = .init()) {
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in Response(catching: { try jsonEncoder.encode(response()) }) })
    }
    
    convenience init<T: Encodable>(uri: String,
                                   returning response: T,
                                   jsonEncoder: JSONEncoder = .init()) {
        let response = Response(catching: { try jsonEncoder.encode(response) })
        self.init(matchingRequest: { $0.uri == uri },
                  handler: { _ in response })
    }
}
