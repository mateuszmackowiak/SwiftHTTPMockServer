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

    private lazy var server = MockServer(stubs: [testStub], unhandledBlock: { request in
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

@MockServer(serverPropertyName: "mordo")
class Helper2ConstructorsTests {
    struct SampleStruct: Codable, Equatable {
        let sample: String
        let data: Date

        init(sample: String = UUID().uuidString, data: Date = Date()) {
            self.sample = sample
            self.data = data
        }
    }
    @Stub(uri: "/test")
    private var testResponse = SampleStruct()
    
    @Stub(uri: "/test2")
    private var elo = "modro"
    
    @Test("ConstructorMockServer returns JSON body and 200")
    func testConstructorMockServer() async throws {
        let request = URLRequest(url: mordo.baseURL.appending(path: "test"))

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        let returned = try JSONDecoder().decode(SampleStruct.self, from: data)
        #expect(returned == testResponse)
        #expect(httpResponse.statusCode == 200)
    }

    @Test("ConstructorMockServer returns JSON body and 200")
    func testConstructorMockServer2() async throws {
        let request = URLRequest(url: mordo.baseURL.appending(path: "test2"))

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        let returned = String(decoding: data, as: UTF8.self)
        #expect(returned == elo)
        #expect(httpResponse.statusCode == 200)
    }
}
#endif
