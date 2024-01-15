//
//
//  Created by Mateusz
//

import XCTest
import HTTPMockServer

final class HTTPServerTests: XCTestCase {
    private lazy var location = (latitude: Double.random(in: -90...90), longitude: Double.random(in: -180...180))
    private lazy var url = URL(string: "http://localhost:\(server.port)/testHTTPServerTests")!
    private lazy var stub = TestLocationServerStub(self.location)

    private lazy var server = MockServer(port: .random(in: 7000...8000), stubs: [
        .requestBearerAuthorizationValidator,
        .requestContentTypeValidator,
        stub
    ], unhandledBlock: {
        XCTFail("Unhandled request \($0)")
    })

    override func setUpWithError() throws {
        try server.start()
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try server.stop()
        try super.tearDownWithError()
    }

    func testSimpleSuccess() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let headers = ["authorization": "Bearer \(UUID().uuidString)", "Content-Type": "application/json"]
        request.allHTTPHeaderFields = headers

        let (data, response) = try await URLSession.shared.data(for: request)
        let expectedData = Data("""
        {
          "location": {
            "coordinates": [\(location.latitude), \(location.longitude)],
            "type": "Point"
          }
        }
        """.utf8)
        XCTAssertEqual(data, expectedData)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)

        XCTAssertEqual(stub.responseHistory, [.success(responseBody: expectedData)])
    }

    func testMissingAuthorizationHeader() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        let responseStruct = try JSONDecoder().decode(ResponseError.self, from: data)
        XCTAssertEqual(responseStruct.code, "Missing Authorisation Bearer header")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 403)
    }

    func testMissingContentTypeHeader() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = ["authorization": "Bearer \(UUID().uuidString)"]

        let (data, response) = try await URLSession.shared.data(for: request)

        let responseStruct = try JSONDecoder().decode(ResponseError.self, from: data)
        XCTAssertEqual(responseStruct.code, "Missing Content-Type header")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 400)
    }

    func testSuccessResponse() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = ["authorization": "Bearer \(UUID().uuidString)", "Content-Type": "application/json"]

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual(data, Data("""
        {
          "location": {
            "coordinates": [\(location.latitude), \(location.longitude)],
            "type": "Point"
          }
        }
        """.utf8))
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
    }

    private struct ResponseError: Decodable, Hashable {
        let code: String
        let message: String
    }
}

extension ServerStub {
    static let requestBearerAuthorizationValidator = RequestBearerAuthorizationValidator()
    static let requestContentTypeValidator = RequestContentTypeValidator()

    final class RequestBearerAuthorizationValidator: ServerStub {
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

    final class RequestContentTypeValidator: ServerStub {
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

fileprivate class TestLocationServerStub: ServerStub {
    public init(_ locationProvider: @escaping @autoclosure () -> (latitude: Double, longitude: Double)) {
        super.init(matchingRequest: {
            $0.method == .GET && $0.uri == "/testHTTPServerTests"
        }) { _ in
            let location = locationProvider()
            return .success(responseBody: Data("""
           {
             "location": {
               "coordinates": [\(location.latitude), \(location.longitude)],
               "type": "Point"
             }
           }
           """.utf8))
        }
    }
}
