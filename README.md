# Swift HTTPMockServer
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-orange.svg)](https://swift.org/package-manager/) [![Swift](https://img.shields.io/badge/Swift-5.5%2B-orange.svg)](https://swift.org) [![iOS](https://img.shields.io/badge/iOS-12%2B-blue.svg)](https://developer.apple.com/ios/) [![macOS](https://img.shields.io/badge/macOS-11%2B-blue.svg)](https://developer.apple.com/macos/) [![SwiftNIO](https://img.shields.io/badge/Powered%20by-SwiftNIO-9cf.svg)](https://github.com/apple/swift-nio)

Swift-nio based server for mocking

[![iOS](https://img.shields.io/badge/iOS->12.0-green.svg)](https://developer.apple.com/ios/)

Lightweight local HTTP server built on SwiftNIO for deterministic API testing — especially UI tests. Simulate network responses in pure Swift by pointing your app to http://localhost:<port>. No external proxies, VPNs, or backend changes. Works with XCTest and the modern Swift Testing framework.

UI tests in pure Swift:
- Start the server in your UI test target (setup/init).
- Pass the server's base URL to the app via launchEnvironment or arguments.
- Keep stubs per test for isolation; use random ports for parallel UI runs.
- Fail fast on unhandled requests to catch unexpected traffic.


##UI Tests
```
import Testing
import HTTPMockServer

let app = XCUIApplication()
app.launchEnvironment["MOCK_SERVER_BASE_URL"] = server.baseURL.absoluteString
app.launch()
```


##Unit Test
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
