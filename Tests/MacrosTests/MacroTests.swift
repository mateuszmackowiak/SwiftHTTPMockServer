#if canImport(Testing)

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import HTTPMockServerMacros
import HTTPMockServer
import Testing

@Suite
struct MockServerMacroTests {
    let testMacros: [String: Macro.Type] = [
        "MockServer": MockServerMacro.self,
        "Stub": ServerStubMemberMacro.self
    ]

    @Test
    func testMockServerMacroExpansion() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub
                var locationStub: TestLocationServerStub = .init()
                
                @Stub
                var listStubs = [AuthServerStub()]
            
                @Stub
                private lazy var stub = TestLocationServerStub()
            }
            """,
            expandedSource: """
            class MyTests {
                var locationStub: TestLocationServerStub = .init()
                
                var listStubs = [AuthServerStub()]
                private lazy var stub = TestLocationServerStub()

                private lazy var _server = MockServer(
                    stubs: [locationStub] + listStubs + [stub],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try _server.start()
                }

                deinit {
                    try! _server.stop()
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func testMockServerMacroForLazyVarExpansion() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub
                private lazy var stub = TestLocationServerStub()
            }
            """,
            expandedSource: """
            class MyTests {
                private lazy var stub = TestLocationServerStub()

                private lazy var _server = MockServer(
                    stubs: [stub],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try _server.start()
                }

                deinit {
                    try! _server.stop()
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func testMockServerMacroExpansion2() {
        assertMacroExpansion(
            """
            @MockServer(serverPropertyName: "mockServer")
            class MyTests {
                @Stub
                private lazy var stubs = [ServerStub.requestBearerAuthorizationValidator, .requestContentTypeValidator, stub]
            }
            """,
            expandedSource: """
            class MyTests {
                private lazy var stubs = [ServerStub.requestBearerAuthorizationValidator, .requestContentTypeValidator, stub]

                private lazy var mockServer = MockServer(
                    stubs: stubs,
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try mockServer.start()
                }

                deinit {
                    try! mockServer.stop()
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test
    func testGetStubMockServerMacroExpansion() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub(uri: "/test")
                private var testResponse = SampleStruct()
            }
            """,
            expandedSource: """
            class MyTests {
                private var testResponse = SampleStruct()
            
                private lazy var _server = MockServer(
                    stubs: [_testResponseStub()],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )
            
                init() throws {
                    try _server.start()
                }
            
                deinit {
                    try! _server.stop()
                }
            
                private func _testResponseStub() -> ServerStub {
                    let resp = self.testResponse
                    return ServerStub(
                        matchingRequest: {
                            $0.uri == "/test"
                        },
                        returning: resp
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test
    func testGetStubMockServerMacroExpansion2() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub(uri: "/test", method: .GET)
                private var testResponse = SampleStruct()
            
                @Stub(uri: "/test2")
                private var secondTestResponse = "response"
            }
            """,
            expandedSource: """
            class MyTests {
                private var testResponse = SampleStruct()
                private var secondTestResponse = "response"

                private lazy var _server = MockServer(
                    stubs: [_testResponseStub()] + [_secondTestResponseStub()],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try _server.start()
                }

                deinit {
                    try! _server.stop()
                }

                private func _testResponseStub() -> ServerStub {
                    let resp = self.testResponse
                    return ServerStub(
                        matchingRequest: {
                            $0.uri == "/test" && $0.method == .GET
                        },
                        returning: resp
                    )
                }

                private func _secondTestResponseStub() -> ServerStub {
                    let resp = self.secondTestResponse
                    return ServerStub(
                        matchingRequest: {
                            $0.uri == "/test2"
                        },
                        returning: resp
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
    @Test
    func testStubWithBlockMockServerMacroExpansion() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub(uri: "/")
                private let block: @Sendable (HTTPRequest) -> ServerStub.Response? = {
                    guard let authorizationHeader = ($0.headers["Authorization"].first ?? $0.headers["authorization"].first),
                          authorizationHeader.hasPrefix("Bearer ") else {
                        return .failure(statusCode: .forbidden, responseError: ResponseError(code: "Missing Authorisation Bearer header", message: "Missing Authorisation Bearer header in \\($0)"))
                    }
                }
            }
            """,
            expandedSource: """
            class MyTests {
                private let block: @Sendable (HTTPRequest) -> ServerStub.Response? = {
                    guard let authorizationHeader = ($0.headers["Authorization"].first ?? $0.headers["authorization"].first),
                          authorizationHeader.hasPrefix("Bearer ") else {
                        return .failure(statusCode: .forbidden, responseError: ResponseError(code: "Missing Authorisation Bearer header", message: "Missing Authorisation Bearer header in \\($0)"))
                    }
                }
            
                private lazy var _server = MockServer(
                    stubs: [_blockStub()],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )
            
                init() throws {
                    try _server.start()
                }
            
                deinit {
                    try! _server.stop()
                }
            
                private func _blockStub() -> ServerStub {
                    let resp = self.block
                    return ServerStub(
                        matchingRequest: {
                            $0.uri == "/"
                        },
                        handler: resp
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
    
    @Test
    func testStubWithFuncMockServerMacroExpansion() {
        assertMacroExpansion(
            """
            @MockServer
            class MyTests {
                @Stub(uri: "*")
                private static func requestContentTypeValidaton(_ request: HTTPRequest) -> ServerStub.Response? {
                    if let header = request.headers["Content-Type"].first {
                        for supportedType in ["application/json", "multipart/form-data"] {
                            if header.hasPrefix(supportedType) {
                                return nil
                            }
                        }
                    }
                    return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Missing Content-Type header", message: "Request \\(request) must provide a valid `Content-Type` header"))
                }
            }
            """,
            expandedSource: """
            class MyTests {
                private static func requestContentTypeValidaton(_ request: HTTPRequest) -> ServerStub.Response? {
                    if let header = request.headers["Content-Type"].first {
                        for supportedType in ["application/json", "multipart/form-data"] {
                            if header.hasPrefix(supportedType) {
                                return nil
                            }
                        }
                    }
                    return .failure(statusCode: .badRequest, responseError: ResponseError(code: "Missing Content-Type header", message: "Request \\(request) must provide a valid `Content-Type` header"))
                }
            
                private lazy var _server = MockServer(
                    stubs: [_requestContentTypeValidatonStub()],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )
            
                init() throws {
                    try _server.start()
                }
            
                deinit {
                    try! _server.stop()
                }

                private func _requestContentTypeValidatonStub() -> ServerStub {
                    return ServerStub(
                        matchingRequest: { _ in
                            return true
                        },
                        handler: Self.requestContentTypeValidaton
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}

#endif
