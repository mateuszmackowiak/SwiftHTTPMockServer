//
//
//  Created by Mateusz
//

#if canImport(Testing)

import Foundation
import Testing
import HTTPMockServer

@Suite
final class ForwardingTests {
    private let upstreamPayload = Data(#"{"forwarded":true,"id":42}"#.utf8)

    private lazy var upstream = MockServer(stubs: [
        ServerStub(matchingRequest: { $0.method == .GET && $0.uri.hasPrefix("/api/items") },
                   handler: { [upstreamPayload] _ in
                       .success(responseBody: upstreamPayload,
                                statusCode: .ok,
                                contentType: "application/json",
                                headers: ["X-Upstream": "yes"])
                   }),
        ServerStub(matchingRequest: { $0.method == .POST && $0.uri == "/echo" },
                   handler: { request in
                       .success(responseBody: request.body.data ?? Data(),
                                statusCode: .created,
                                contentType: "application/octet-stream")
                   }),
        ServerStub(matchingRequest: { $0.uri == "/boom" },
                   handler: { _ in
                       .failure(statusCode: .internalServerError,
                                responseError: ResponseError(code: "boom", message: "upstream failed"))
                   })
    ], unhandledBlock: { Issue.record("Upstream received unhandled request \($0)") })

    private lazy var proxy = MockServer(stubs: [
        ServerStub(forwardingTo: upstream.baseURL)
    ], unhandledBlock: { Issue.record("Proxy received unhandled request \($0)") })

    init() throws {
        try upstream.start()
        try proxy.start()
    }

    deinit {
        try? proxy.stop()
        try? upstream.stop()
    }

    @Test("GET is forwarded and upstream response is returned verbatim")
    func testForwardsGET() async throws {
        let url = proxy.baseURL.appending(path: "api/items").appending(queryItems: [URLQueryItem(name: "page", value: "2")])
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        #expect(data == upstreamPayload)
        #expect((httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("application/json"))
        #expect(httpResponse.value(forHTTPHeaderField: "X-Upstream") == "yes")
    }

    @Test("POST body and method are forwarded; upstream status is preserved")
    func testForwardsPOSTBody() async throws {
        var request = URLRequest(url: proxy.baseURL.appending(path: "echo"))
        request.httpMethod = "POST"
        request.httpBody = Data("hello-upstream".utf8)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 201)
        #expect(data == Data("hello-upstream".utf8))
    }

    @Test("Upstream failure status is preserved through the forward")
    func testForwardsFailureStatus() async throws {
        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: proxy.baseURL.appending(path: "boom")))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 500)
    }

    @Test("Bad gateway when upstream is unreachable")
    func testBadGatewayOnUnreachable() async throws {
        let deadServer = MockServer(stubs: [])
        let unreachable = deadServer.baseURL

        let proxyToNowhere = MockServer(stubs: [
            ServerStub(forwardingTo: unreachable, timeout: 1)
        ])
        try await proxyToNowhere.start()
        defer { try? proxyToNowhere.stop() }

        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: proxyToNowhere.baseURL.appending(path: "anything")))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 502)
    }
}

#endif
