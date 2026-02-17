//
//
//  Created by Mateusz
//

public final class PrintLogger: Logger {
    public init() {}

    public func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let file = file.split(separator: "/").last.map(String.init) ?? file
        let message = "\(file): \(message)"
        print(message)
    }
}

public protocol Logger: Sendable {
    func log(_ message: String, file: String, function: String, line: Int)
}

public extension Logger {
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(message, file: file, function: function, line: line)
    }
}
