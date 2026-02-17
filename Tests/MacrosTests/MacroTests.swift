import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import HTTPMockServerMacros
import HTTPMockServer
import Testing

@Suite
struct MockServerMacroTests {
    let testMacros: [String: Macro.Type] = [
        "MockServer": MockServerMacro.self
    ]

    class AuthServerStub: ServerStub, @unchecked Sendable {}
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
            }
            """,
            expandedSource: """
            class MyTests {
                @Stub
                var locationStub: TestLocationServerStub = .init()
                
                @Stub
                var listStubs = [AuthServerStub()]

                private lazy var server = MockServer(
                    stubs: [locationStub] + listStubs,
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try server.start()
                }

                deinit {
                    try! server.stop()
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func testMockServerMacroWithNoStubs() {
        assertMacroExpansion(
            """
            @MockServer
            class EmptyTests {
            }
            """,
            expandedSource: """
            class EmptyTests {

                private lazy var server = MockServer(
                    stubs: [stubs],
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try server.start()
                }

                deinit {
                    try! server.stop()
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
            @MockServer
            class MyTests {
                @Stub
                private lazy var stubs = [ServerStub.requestBearerAuthorizationValidator, .requestContentTypeValidator, stub]
            }
            """,
            expandedSource: """
            class MyTests {
                @Stub
                private lazy var stubs = [ServerStub.requestBearerAuthorizationValidator, .requestContentTypeValidator, stub]

                private lazy var server = MockServer(
                    stubs: stubs,
                    unhandledBlock: { request in
                        Issue.record("Unhandled request \\(request)")
                    }
                )

                init() throws {
                    try server.start()
                }

                deinit {
                    try! server.stop()
                }
            }
            """,
            macros: testMacros
        )
    }
    
    
}
