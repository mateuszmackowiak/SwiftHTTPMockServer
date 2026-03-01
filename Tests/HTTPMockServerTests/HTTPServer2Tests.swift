//
//
//  Created by Mateusz
//

#if canImport(Testing)

import Foundation
import Testing
import HTTPMockServer

@Suite
@MockServer
final class HTTPServer2Tests {
    private let location = (latitude: Double.random(in: -90...90), longitude: Double.random(in: -180...180))
        
    @Stub
    private let requestBearerAuthorizationValidation: @Sendable (HTTPRequest) -> ServerStub.Response? = {
        guard let authorizationHeader = ($0.headers["Authorization"].first ?? $0.headers["authorization"].first),
              authorizationHeader.hasPrefix("Bearer ") else {
            return .failure(statusCode: .forbidden, responseError: ResponseError(code: "Missing Authorisation Bearer header", message: "Missing Authorisation Bearer header in \($0)"))
        }
        return nil
    }
    
    @Stub
    private static func requestContentTypeValidaton(_ request: HTTPRequest) -> ServerStub.Response? {
        if let header = request.headers["Content-Type"].first {
            for supportedType in ["application/json", "multipart/form-data"] {
                if header.hasPrefix(supportedType) {
                    return nil
                }
            }
        }
        return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Missing Content-Type header", message: "Request \(request) must provide a valid `Content-Type` header"))
    }
    @Stub
    private lazy var stub = TestLocationServerStub(location)

    private lazy var url = _server.baseURL.appending(path: "testHTTPServerTests")
    
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

#endif

