# Swift HTTPMockServer

Swift-nio based server for mocking

[![iOS](https://img.shields.io/badge/iOS->12.0-green.svg)](https://developer.apple.com/ios/)

```swift 

struct SampleStruct: Encodable {
    let sample: String = UUID().uuidString
    let data: Date = Date()
}

final class Tests: XCTestCase {
    
    private lazy var testResponse = SampleStruct()
    private lazy var testStub = ServerStub(uri: "/test", returning: self.testResponse)

    private lazy var server = MockServer(port: Int.random(in: 6000...8000), stubs: [testStub], unhandledBlock: {
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

    func testConstructorMockServer() async throws {
        let request = URLRequest(url: URL(string: "http://localhost:\(server.port)/test")!)

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(data, try JSONEncoder().encode(testResponse))
        XCTAssertEqual(httpResponse.statusCode, 200)
    }
}
```
