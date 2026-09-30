//
//
//  Created by Bartosz
//

#if canImport(Testing)

import Foundation
import Testing
import HTTPMockServer

@Suite
@MockServer
final class ConnectionDroppedTests {
    @Stub
    private lazy var droppedStub = ServerStub(matchingRequest: { $0.uri == "/connectionDroppedTests/dropped" },
                                              handler: { _ in .connectionDropped })

    @Stub(uri: "/connectionDroppedTests/ok")
    let okResponse = ServerStub.Response.success(responseBody: Data(#"{ "ok": true }"#.utf8))

    private lazy var url = _server.baseURL.appending(path: "connectionDroppedTests")

    @Test("Dropped connection surfaces as a transport error, not an HTTP response")
    func testConnectionDropped() async throws {
        let request = URLRequest(url: url.appending(path: "dropped"))

        do {
            _ = try await URLSession.shared.data(for: request)
            Issue.record("Expected the dropped connection to fail the request")
        } catch let error as URLError {
            #expect(error.code == .networkConnectionLost)
        }
        // URLSession retries an idempotent request on a lost connection, so expect one or more drops.
        #expect(!droppedStub.responseHistory.isEmpty)
    }

    @Test("Other stubs keep answering after a connection was dropped")
    func testServerKeepsServingAfterDrop() async throws {
        _ = try? await URLSession.shared.data(for: URLRequest(url: url.appending(path: "dropped")))
        #expect(droppedStub.responseHistory.contains(.connectionDropped))

        let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url.appending(path: "ok")))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
    }
}

#endif
