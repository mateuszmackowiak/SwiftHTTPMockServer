import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct MockServerMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        let serverPropertyName = (arguments?.first(where: { $0.label?.text == "serverPropertyName" })?.expression.description.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? "_server"

        var expansions: [ServerStubMemberMacro.StructuredExpansion] = []
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                try funcDecl.attributes.forEach { attr in

                    guard let attribute = attr.as(AttributeSyntax.self),
                          let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
                          identifier.name.text == "Stub" else {
                        return
                    }
                    if let mordo = try ServerStubMemberMacro.structuredExpansion(generate: true, of: attribute, providingPeersOf: member.decl, in: context) {
                        expansions.append(mordo)
                    }
                }
            }
                if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                    try varDecl.attributes.forEach { attr in
                        guard let attribute = attr.as(AttributeSyntax.self),
                              let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
                              identifier.name.text == "Stub" else {
                            return
                        }
                        if identifier.name.text == "Stub" {
                            if let mordo = try ServerStubMemberMacro.structuredExpansion(generate: true, of: attribute, providingPeersOf: member.decl, in: context) {
                                expansions.append(mordo)
                            }
                        }
                    }
            }
        }

    let collectedStubExprs = expansions.map(\.stubName)
        let combinedStubsExpr: ExprSyntax = {
            if collectedStubExprs.isEmpty {
                return ExprSyntax("[]")
            }
            var expr = collectedStubExprs[0]
            for p in collectedStubExprs.dropFirst() {
                expr = ExprSyntax("\(expr) + \(p)")
            }
            return expr
        }()

        let additional = expansions.compactMap(\.declaration)
        return [
            DeclSyntax("""
            private lazy var \(raw: serverPropertyName) = MockServer(
                stubs: \(combinedStubsExpr),
                unhandledBlock: { request in
                    Issue.record("Unhandled request \\(request)")
                }
            )
            """),

            DeclSyntax("""
            init() throws {
                try \(raw: serverPropertyName).start()
            }
            """),

            DeclSyntax("""
            deinit {
                try! \(raw: serverPropertyName).stop()
            }
            """)
        ] + additional
    }
}
