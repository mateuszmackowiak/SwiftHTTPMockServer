import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct MockServerMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var collectedStubExprs: [ExprSyntax] = []

        outerLoop: for member in declaration.memberBlock.members {
                guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
                
                let hasStubAttribute = varDecl.attributes.contains { attr in
                    guard let attribute = attr.as(AttributeSyntax.self),
                          let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else { return false }
                    
                    return identifier.name.text == "Stub"
                }
                if !hasStubAttribute { continue }
                
                for binding in varDecl.bindings {
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                        continue
                    }
                    let varName = pattern.identifier.text
                    
                    if let typeAnno = binding.typeAnnotation?.type {
                        let typeName = typeAnno.trimmedDescription

                        let isServerStub = typeName.contains("ServerStub")
                        let isArrayOfStubs = typeName.contains("[") && typeName.contains("ServerStub")
                        
                        if isArrayOfStubs {
                            collectedStubExprs.append("\(raw: varName)")
                        } else if isServerStub {
                            collectedStubExprs.append("[\(raw: varName)]")
                        }
                        
                    } else {
                        if let initializer = binding.initializer {
                            if let callExpr = initializer.value.as(FunctionCallExprSyntax.self),
                               let identifier = callExpr.calledExpression.as(DeclReferenceExprSyntax.self) {
                                let typeName = identifier.baseName.text
                                
                                let isServerStub = typeName.contains("ServerStub")
                                let isArrayOfStubs = typeName.contains("[") && typeName.contains("ServerStub")
                                
                                if isArrayOfStubs {
                                    collectedStubExprs.append("\(raw: varName)")
                                } else if isServerStub {
                                    collectedStubExprs.append("[\(raw: varName)]")
                                }
                                
                            } else if let memberAccess = initializer.value.as(MemberAccessExprSyntax.self),
                               let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                                let typeName = base.baseName.text
                                
                                let isServerStub = typeName.contains("ServerStub")
                                let isArrayOfStubs = typeName.contains("[") && typeName.contains("ServerStub")
                                
                                if isArrayOfStubs {
                                    collectedStubExprs.append("\(raw: varName)")
                                } else if isServerStub {
                                    collectedStubExprs.append("[\(raw: varName)]")
                                }
                            } else if let arrayExpr = initializer.value.as(ArrayExprSyntax.self) {
                                for element in arrayExpr.elements {
                                    if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                                        
                                        if let baseExpr = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                                            let baseTypeName = baseExpr.baseName.text
                                            
                                            if baseTypeName == "ServerStub" {
                                                let varName = pattern.identifier.text
                                                collectedStubExprs.append("\(raw: varName)")
                                                
                                            }
                                        }
                                    }
                                    let expression = element.expression
                                    
                                    if let call = expression.as(FunctionCallExprSyntax.self),
                                       let typeName = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text {
                                        
                                        let isServerStub = typeName.contains("ServerStub")
                                        
                                        if isServerStub {
                                            collectedStubExprs.append("\(raw: varName)")
                                            
                                        }
                                    }
                                }
                            }
                        }
                            
                    }
                }
            }
    
        var parts: [ExprSyntax] = []
        parts.append(contentsOf: collectedStubExprs)

        let combinedStubsExpr: ExprSyntax = {
            if parts.isEmpty {
                return ExprSyntax("[stubs]")
            }
            var expr = parts[0]
            for p in parts.dropFirst() {
                expr = ExprSyntax("\(expr) + \(p)")
            }
            return expr
        }()
        
        let serverPropertyName = "server"

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
        ]
    }
}
