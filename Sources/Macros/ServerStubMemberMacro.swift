import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A marker macro used to annotate properties that provide `ServerStub` instances.
/// This macro performs no code generation by itself; it exists so other macros
/// (like `MockServerMacro`) can discover annotated members during expansion.
public struct ServerStubMemberMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro intentionally produces nothing.
        return []
    }
}
