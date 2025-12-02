//
//
//  Created by Mateusz
//

#if canImport(Testing)
import Testing
import Foundation
import HTTPMockServer

@Suite("HelperConstructorsTests")
class HelperConstructorsTests {
    private var testStub: ServerStub { ServerStub(uri: "/test", returning: "testBody") }

    private lazy var server = MockServer(port: Int.random(in: 6000...8000), stubs: [testStub], unhandledBlock: { request in
        Issue.record("Unhandled request \(request)")
    })

    init() throws {
        try server.start()
    }

    deinit {
        try! server.stop()
    }

    @Test("ConstructorMockServer returns body and 200")
    func testConstructorMockServer() async throws {
        let request = URLRequest(url: server.baseURL.appendingPathComponent("/test"))

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(data == Data("testBody".utf8))
        #expect(httpResponse.statusCode == 200)
    }
}

@Suite("Helper2ConstructorsTests")
class Helper2ConstructorsTests {
    struct SampleStruct: Encodable, Equatable {
        let sample: String
        let data: Date

        init(sample: String = UUID().uuidString, data: Date = Date()) {
            self.sample = sample
            self.data = data
        }
    }

    private var testResponse = SampleStruct()
    private var testStub: ServerStub { ServerStub(uri: "/test", returning: self.testResponse) }

    private var server: MockServer!

    init() {
        server = MockServer(port: Int.random(in: 6000...8000), stubs: [testStub], unhandledBlock: { request in
            Issue.record("Unhandled request \(request)")
        })
        try! server.start()
    }

    deinit {
        try! server.stop()
    }

    @Test("ConstructorMockServer returns JSON body and 200")
    func testConstructorMockServer() async throws {
        let request = URLRequest(url: server.baseURL.appending(path: "test"))

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        let expected = try JSONEncoder().encode(testResponse)
        #expect(data == expected)
        #expect(httpResponse.statusCode == 200)
    }
}
#endif
