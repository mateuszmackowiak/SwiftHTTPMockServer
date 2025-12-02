//
//
//  Created by Mateusz
//
#if canImport(XCTest)

import XCTest
import HTTPMockServer

final class POSTTests: XCTestCase {
    private lazy var postTestStub = ServerStub(matchingRequest: { $0.method == .POST }, handler: {
        guard let data = $0.body.data else {
            return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Incomplete data", message: "Incomplete data \($0)"))
        }
        return .success(responseBody: data, statusCode: .ok)
    })
    private lazy var server = MockServer(port: Int.random(in: 6000...8000), stubs: [postTestStub], unhandledBlock: { head in
        XCTFail("Unhandled request \(head)")
    })
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try server.start()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        try server.stop()
    }

    func testPostToLocalhostMockServer() async throws {
        var request = URLRequest(url: server.baseURL.appending(path: "test"))
        request.httpMethod = "POST"
        let requestStruct = TestStruct(key: "test")
        request.httpBody = try JSONEncoder().encode(requestStruct)

        let (data, response) = try await URLSession.shared.data(for: request)

        let responseStruct = try JSONDecoder().decode(TestStruct.self, from: data)
        XCTAssertEqual(responseStruct, requestStruct)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
    }

    private struct TestStruct: Codable, Hashable {
        let key: String
        var id: UUID = UUID()
    }
}

#endif
