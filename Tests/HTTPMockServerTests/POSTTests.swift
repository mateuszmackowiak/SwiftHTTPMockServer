//
//
//  Created by Mateusz
//

import Foundation
import Testing
import HTTPMockServer

@Suite
final class POSTTests {
    private lazy var postTestStub = ServerStub(matchingRequest: { $0.method == .POST }, handler: {
        guard let data = $0.body.data else {
            return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Incomplete data", message: "Incomplete data \($0)"))
        }
        return .success(responseBody: data, statusCode: .ok)
    })
    private lazy var server = MockServer(port: Int.random(in: 6000...8000), stubs: [postTestStub], unhandledBlock: { head in
        Issue.record("Unhandled request \(head)")
    })
    
    init() throws {
        try server.start()
    }
    
    deinit {
        try! server.stop()
    }

    @Test("POST echoes body and returns 200")
    func testPostToLocalhostMockServer() async throws {
        var request = URLRequest(url: server.baseURL.appending(path: "test"))
        request.httpMethod = "POST"
        let requestStruct = TestStruct(key: "test")
        request.httpBody = try JSONEncoder().encode(requestStruct)

        let (data, response) = try await URLSession.shared.data(for: request)

        let responseStruct = try JSONDecoder().decode(TestStruct.self, from: data)
        #expect(responseStruct == requestStruct)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
    }

    private struct TestStruct: Codable, Hashable {
        let key: String
        var id: UUID = UUID()
    }
}
