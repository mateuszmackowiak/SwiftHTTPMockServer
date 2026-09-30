# Swift HTTPMockServer
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-orange.svg)](https://swift.org/package-manager/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org) [![iOS](https://img.shields.io/badge/iOS-15%2B-blue.svg)](https://developer.apple.com/ios/) [![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://developer.apple.com/macos/) [![SwiftNIO](https://img.shields.io/badge/Powered%20by-SwiftNIO-9cf.svg)](https://github.com/apple/swift-nio)

Swift-nio based server for mocking

Lightweight local HTTP server built on SwiftNIO for deterministic API testing — especially UI tests. Simulate network responses in pure Swift by pointing your app to http://localhost:<port>. No external proxies, VPNs, or backend changes. Works with XCTest and the modern Swift Testing framework.

UI tests in pure Swift:
- Start the server in your UI test target (setup/init).
- Pass the server's base URL to the app via launchEnvironment or arguments.
- Keep stubs per test for isolation; use random ports for parallel UI runs.
- Fail fast on unhandled requests to catch unexpected traffic.


## UI Tests

```swift
  let stub = ServerStub(uri: "/hello", returning: ["ok": true])
  let server = MockServer(stubs: [stub]) { Issue.record("Unhandled \($0)") }
  try server.start(); defer { try? server.stop() }

  // In UI tests:
  let app = XCUIApplication()
  app.launchEnvironment["MOCK_SERVER_BASE_URL"] = server.baseURL.absoluteString
  app.launch()
```


## Dropped connection

Close the connection without a response to simulate a network failure. The client gets a transport error (`URLError.networkConnectionLost`) rather than an HTTP status — useful for WebViews, which render any HTTP error page instead of failing the navigation.

```swift
@MockServer
final class OfflineTests {
    @Stub(uri: "/some/path")
    let dropped = ServerStub.Response.connectionDropped
}
```

Without the macros:

```swift
  let dropped = ServerStub(matchingRequest: { $0.uri.hasPrefix("/some/path") },
                           handler: { _ in .connectionDropped })
```

- Clients retry an idempotent request after a lost connection (URLSession made three attempts for one GET), so keep dropping for as long as the test needs the failure — dropping only the first attempt lets the retry succeed. `responseHistory` records every attempt, not every client call.
- To stop dropping mid-test, return `nil` from the handler based on state the test owns; `nil` passes the request on to the next stub.
- `@Stub(uri:)` compares the raw request target, query string included — use `matchingRequest` for a path that may carry a query.
- Stubs are tried in declaration order and the first non-`nil` response wins, so declare the drop before a catch-all forwarding stub.


## Unit Test
```swift
struct SampleStruct: Encodable {
    let sample: String = UUID().uuidString
    let data: Date = Date()
}
```

```swift 
import Foundation
import Testing
import HTTPMockServer

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
```
