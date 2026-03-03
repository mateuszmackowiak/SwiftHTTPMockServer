import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct MockServerMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(node: Syntax(declaration),
                           message: SimpleDiagnosticsMessage(message: "@MockServer can only be applied to a class declaration."))
            )
            return []
        }

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

        let inheritsFromXCTestCase = classDecl.inheritanceClause?.inheritedTypes.contains { inheritedType in
            let typeName = inheritedType.type.trimmedDescription
            return typeName == "XCTestCase"
        } ?? false

        let failureRecording = inheritsFromXCTestCase
        ? "XCTFail(\"Unhandled request \\(request)\")"
        : "Issue.record(\"Unhandled request \\(request)\")"

        let existingMembers = classDecl.memberBlock.members

        let hasInit = existingMembers.contains { $0.decl.is(InitializerDeclSyntax.self) }
        let hasDeinit = existingMembers.contains { $0.decl.is(DeinitializerDeclSyntax.self) }

        let hasSetUp = existingMembers.contains { member in
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                return funcDecl.name.text == "setUpWithError"
            }
            return false
        }

        let hasTearDown = existingMembers.contains { member in
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                return funcDecl.name.text == "tearDownWithError"
            }
            return false
        }

        let serverDeclaration = DeclSyntax("""
            private lazy var \(raw: serverPropertyName) = MockServer(
                stubs: \(combinedStubsExpr),
                unhandledBlock: { request in
                    \(raw: failureRecording)
                }
            )
            """)
        var members: [DeclSyntax] = [serverDeclaration]

        if inheritsFromXCTestCase {
            if !hasSetUp {
                members.append(DeclSyntax("""
                            override func setUpWithError() throws {
                                try super.setUpWithError()
                                try \(raw: serverPropertyName).start()
                            }
                            """))
            }
            if !hasTearDown {
                members.append(DeclSyntax("""
                            override func tearDownWithError() throws {
                                try \(raw: serverPropertyName).stop()
                                try super.tearDownWithError()
                            }
                            """))
            }
        } else {
            if !hasInit {
                members.append(DeclSyntax("""
                            init() throws {
                                try \(raw: serverPropertyName).start()
                            }
                            """))
            }
            if !hasDeinit {
                members.append(DeclSyntax("""
                            deinit {
                                try! \(raw: serverPropertyName).stop()
                            }
                            """))
            }
        }
        return members + expansions.compactMap(\.declaration)
    }
}
