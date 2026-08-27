#if canImport(XCTest)

import XCTest
import HTTPMockServer

@MockServer
@MainActor
final class MainActorXCTests: XCTestCase {
    private let path = "main-actor"

    @Stub(uri: "/main-actor")
    private lazy var mainActorStub = ServerStub.Response.success(responseBody: Data(path.utf8), statusCode: .ok)

    func testGetFromMainActorIsolatedTestCase() async throws {
        let (data, response) = try await URLSession.shared.data(from: _server.baseURL.appending(path: path))

        XCTAssertEqual(String(decoding: data, as: UTF8.self), path)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
    }
}

#endif
