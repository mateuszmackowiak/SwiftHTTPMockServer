//
//
//  Created by Mateusz
//

#if canImport(Testing)

import Foundation
import Testing
import HTTPMockServer

@Suite
final class HTTPServerTests {
    private struct ResponseError: Decodable, Hashable {
        let code: String
        let message: String
    }
    
    private let location = (latitude: Double.random(in: -90...90), longitude: Double.random(in: -180...180))
    private lazy var stub = TestLocationServerStub(self.location)
    private lazy var url = server.baseURL.appending(path: "testHTTPServerTests")
    private lazy var server = MockServer(port: .random(in: 7000...8000), stubs: [
        .requestBearerAuthorizationValidator,
        .requestContentTypeValidator,
        stub
    ], unhandledBlock: { head in
        Issue.record("Unhandled request \(head)")
    })
    
    init() throws {
        try server.start()
    }
    
    deinit {
        try! server.stop()
    }
    
    
    @Test("GET succeeds with valid headers and body matches expected JSON")
    func testSimpleSuccess() async throws {
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["authorization": "Bearer \(UUID().uuidString)", "Content-Type": "application/json"]
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let expectedData = Data("""
        {
          "location": {
            "coordinates": [\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))],
            "type": "Point"
          }
        }
        """.utf8)
        #expect(data == expectedData)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        
        #expect(stub.responseHistory == [.success(responseBody: expectedData)])
    }
    
    @Test("403 when Authorization header missing")
    func testMissingAuthorizationHeader() async throws {
        let request = URLRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let responseStruct = try JSONDecoder().decode(ResponseError.self, from: data)
        #expect(responseStruct.code == "Missing Authorisation Bearer header")
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 403)
    }
    
    
    @Test("400 when Content-Type header missing")
    func testMissingContentTypeHeader() async throws {
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["authorization": "Bearer \(UUID().uuidString)"]
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let responseStruct = try JSONDecoder().decode(ResponseError.self, from: data)
        #expect(responseStruct.code == "Missing Content-Type header")
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 400)
    }
    
    @Test("200 when both headers provided")
    func testSuccessResponse() async throws {
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["authorization": "Bearer \(UUID().uuidString)", "Content-Type": "application/json"]
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let expectedData = Data("""
        {
          "location": {
            "coordinates": [\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))],
            "type": "Point"
          }
        }
        """.utf8)
        #expect(data == expectedData)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
    }
}

extension ServerStub {
    static let requestBearerAuthorizationValidator = RequestBearerAuthorizationValidator()
    static let requestContentTypeValidator = RequestContentTypeValidator()
    
    final class RequestBearerAuthorizationValidator: ServerStub, @unchecked Sendable {
        init() {
            super.init(matchingRequest: { _ in true }) {
                guard let authorizationHeader = ($0.headers["Authorization"].first ?? $0.headers["authorization"].first),
                      authorizationHeader.hasPrefix("Bearer ") else {
                    return .failure(statusCode: .forbidden, responseError: ResponseError(code: "Missing Authorisation Bearer header", message: "Missing Authorisation Bearer header in \($0)"))
                }
                return nil
            }
        }
    }
    
    final class RequestContentTypeValidator: ServerStub, @unchecked Sendable {
        public let supportedTypes: [String]
        
        init(supportedTypes: [String] = ["application/json", "multipart/form-data"]) {
            self.supportedTypes = supportedTypes
            
            super.init(matchingRequest: { _ in true }) { head in
                if let header = head.headers["Content-Type"].first {
                    for supportedType in supportedTypes {
                        if header.hasPrefix(supportedType) {
                            return nil
                        }
                    }
                }
                return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Missing Content-Type header", message: "Request \(head) must provide a valid `Content-Type` header"))
            }
        }
    }
}

fileprivate class TestLocationServerStub: ServerStub, @unchecked Sendable {
    public init(_ location: (latitude: Double, longitude: Double)) {
        super.init(matchingRequest: {
            $0.method == .GET && $0.uri == "/testHTTPServerTests"
        }, handler: { _ in
            return .success(responseBody: Data("""
           {
             "location": {
               "coordinates": [\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))],
               "type": "Point"
             }
           }
           """.utf8))
        })
    }
}

import Foundation
import Testing
import HTTPMockServer

struct SampleStruct: Encodable {
    let sample: String = UUID().uuidString
    let data: Date = Date()
}

@Suite
final class Tests {
    private lazy var testResponse = SampleStruct()
    private lazy var testStub = ServerStub(uri: "/test", returning: self.testResponse)

    private lazy var server = MockServer(stubs: [testStub], unhandledBlock: { Issue.record("Unhandled request \($0)") })

    init() throws {
        try server.start()
    }
    
    deinit {
        try! server.stop()
    }

    func testConstructorMockServer() async throws {
        let request = URLRequest(url: URL(string: "http://localhost:\(server.port)/test")!)

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        let expected = try JSONEncoder().encode(testResponse)
        #expect(data == expected)
        #expect(httpResponse.statusCode ==  200)
    }
}

#endif

