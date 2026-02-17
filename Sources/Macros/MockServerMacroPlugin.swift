import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct MockServerMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockServerMacro.self, ServerStubMemberMacro.self
    ]
}
