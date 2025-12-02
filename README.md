# Swift HTTPMockServer

Swift-nio based server for mocking

[![iOS](https://img.shields.io/badge/iOS->12.0-green.svg)](https://developer.apple.com/ios/)

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
