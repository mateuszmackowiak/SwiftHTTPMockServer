import SwiftDiagnostics

struct SimpleDiagnosticsMessage: DiagnosticMessage {
    let message: String
    let domain: StaticString

    init(message: String, domain: StaticString = #file) {
        self.message = message
        self.domain = domain
    }
    var diagnosticID: MessageID {
        MessageID(domain: "\(domain)", id: message)
    }

    var severity: DiagnosticSeverity { .error }
}
