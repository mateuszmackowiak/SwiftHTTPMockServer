//
//
//  Created by Mateusz
//

import Foundation
import NIOHTTP1

public extension ServerStub {
    /// Forwards matching requests to `targetBaseURL` and replays the upstream response as the stub's response.
    ///
    /// The forwarded request preserves the original method, headers (minus hop-by-hop), body, and the request URI
    /// appended to `targetBaseURL`'s path. The handler blocks on the NIO event loop until the upstream responds
    /// or `timeout` elapses.
    convenience init(matchingRequest: @Sendable @escaping (HTTPRequest) -> Bool,
                     forwardingTo targetBaseURL: URL,
                     urlSession: URLSession = .shared,
                     timeout: TimeInterval = 30) {
        self.init(matchingRequest: matchingRequest,
                  handler: ServerStub.makeForwardingHandler(targetBaseURL: targetBaseURL,
                                                            urlSession: urlSession,
                                                            timeout: timeout))
    }

    /// Forwards every request to `targetBaseURL` — a transparent proxy stub. Place after validators and before more specific stubs as needed.
    convenience init(forwardingTo targetBaseURL: URL,
                     urlSession: URLSession = .shared,
                     timeout: TimeInterval = 30) {
        self.init(matchingRequest: { _ in true },
                  forwardingTo: targetBaseURL,
                  urlSession: urlSession,
                  timeout: timeout)
    }

    /// Forwards requests whose `uri` matches the given string to `targetBaseURL`.
    convenience init(uri: String,
                     forwardingTo targetBaseURL: URL,
                     urlSession: URLSession = .shared,
                     timeout: TimeInterval = 30) {
        self.init(matchingRequest: { $0.uri == uri },
                  forwardingTo: targetBaseURL,
                  urlSession: urlSession,
                  timeout: timeout)
    }

    private static func makeForwardingHandler(targetBaseURL: URL,
                                              urlSession: URLSession,
                                              timeout: TimeInterval) -> @Sendable (HTTPRequest) -> Response? {
        return { request in
            guard let forwardURL = combine(targetBaseURL: targetBaseURL, requestURI: request.uri) else {
                return .failure(statusCode: .badGateway,
                                responseError: ResponseError(code: "ForwardingStub_InvalidURL",
                                                             message: "Cannot build forward URL from \(targetBaseURL) + \(request.uri)"))
            }

            var urlRequest = URLRequest(url: forwardURL, timeoutInterval: timeout)
            urlRequest.httpMethod = request.method.rawValue
            for header in request.headers {
                if hopByHopHeaders.contains(header.name.lowercased()) { continue }
                urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
            }
            if let bodyData = request.body.data, !bodyData.isEmpty {
                urlRequest.httpBody = bodyData
            }

            let box = ForwardingResultBox()
            let semaphore = DispatchSemaphore(value: 0)
            let task = urlSession.dataTask(with: urlRequest) { data, response, error in
                box.data = data
                box.response = response
                box.error = error
                semaphore.signal()
            }
            task.resume()

            let waitNanos = max(0, Int64(timeout * 1_000_000_000))
            if semaphore.wait(timeout: .now() + .nanoseconds(Int(waitNanos))) == .timedOut {
                task.cancel()
                return .failure(statusCode: .gatewayTimeout,
                                responseError: ResponseError(code: "ForwardingStub_Timeout",
                                                             message: "Upstream \(forwardURL) did not respond within \(timeout)s"))
            }

            if let error = box.error {
                return .failure(statusCode: .badGateway,
                                responseError: ResponseError(code: "ForwardingStub_RequestError",
                                                             message: String(describing: error)))
            }
            guard let httpResponse = box.response as? HTTPURLResponse else {
                return .failure(statusCode: .badGateway,
                                responseError: ResponseError(code: "ForwardingStub_NoResponse",
                                                             message: "No HTTPURLResponse from \(forwardURL)"))
            }

            var headers: [String: String] = [:]
            var contentType = "application/octet-stream"
            for (key, value) in httpResponse.allHeaderFields {
                guard let keyString = key as? String, let valueString = value as? String else { continue }
                let lower = keyString.lowercased()
                if hopByHopHeaders.contains(lower) || lower == "content-length" { continue }
                if lower == "content-type" {
                    contentType = valueString
                    continue
                }
                headers[keyString] = valueString
            }

            return .success(responseBody: box.data ?? Data(),
                            statusCode: HTTPResponseStatus(statusCode: httpResponse.statusCode),
                            contentType: contentType,
                            headers: headers)
        }
    }
}

private final class ForwardingResultBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}

private let hopByHopHeaders: Set<String> = [
    "connection",
    "keep-alive",
    "transfer-encoding",
    "upgrade",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "host"
]

private func combine(targetBaseURL: URL, requestURI: String) -> URL? {
    guard var targetComponents = URLComponents(url: targetBaseURL, resolvingAgainstBaseURL: false) else {
        return nil
    }
    let incomingComponents = URLComponents(string: requestURI)
    let incomingPath = incomingComponents?.path ?? requestURI
    let incomingQuery = incomingComponents?.percentEncodedQuery

    let basePath = targetComponents.path
    let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
    let normalizedIncoming = incomingPath.hasPrefix("/") ? incomingPath : "/" + incomingPath
    targetComponents.path = trimmedBase + normalizedIncoming
    if let incomingQuery {
        targetComponents.percentEncodedQuery = incomingQuery
    }
    return targetComponents.url
}
