import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// A marker macro used to annotate properties that provide `Stub` instances.
/// This macro performs no code generation by itself; it exists so other macros
/// (like `MockServerMacro`) can discover annotated members during expansion.
public struct ServerStubMemberMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return []
    }

    enum StructuredExpansion {
        case withAdditionalDeclaration(stubName: ExprSyntax, declaration: DeclSyntax)
        case singleStub(stubName: ExprSyntax)
        case collectionStub(stubName: ExprSyntax)

        var stubName: ExprSyntax {
            switch self {
            case .singleStub(let stubName):
                return ExprSyntax("[\(stubName)]")
            case .collectionStub(let stubName):
                return stubName
            case .withAdditionalDeclaration(let stubName, _):
                return ExprSyntax("[\(stubName)]")
            }
        }
        var declaration: DeclSyntax? {
            switch self {
            case .collectionStub, .singleStub:
                return nil
            case .withAdditionalDeclaration(_, let declaration):
                return declaration
            }
        }

        init(stubName: ExprSyntax, declaration: DeclSyntax) {
            self = .withAdditionalDeclaration(stubName: stubName, declaration: declaration)
        }
    }

    static func structuredExpansion(
        generate: Bool,
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> StructuredExpansion? {
        let validationExpresion = validationExpresion(of: node)
        if let variable = declaration.as(VariableDeclSyntax.self) {
            return try variableExpansion(of: node, providingPeersOf: variable, in: context, validationExpresion: validationExpresion)
        }
        if let function = declaration.as(FunctionDeclSyntax.self), function.modifiers.contains (where: { $0.name.tokenKind == .keyword(.static) }) {
            return functionExpansion(of: node, providingPeersOf: function, in: context, validationExpresion: validationExpresion)
        }
        return nil
    }

    private static func functionExpansion(
        of node: AttributeSyntax,
        providingPeersOf variable: FunctionDeclSyntax,
        in context: some MacroExpansionContext,
        validationExpresion: ExprSyntax
    ) -> StructuredExpansion {
        let name = variable.name
        let stubName = ExprSyntax("_\(name)Stub()")
        return StructuredExpansion(stubName: stubName,
                                   declaration:
                                    DeclSyntax(
                   """
                   private func \(stubName) -> ServerStub {
                       return ServerStub(
                           matchingRequest: \(validationExpresion),
                           handler: Self.\(raw: name)
                   )
                   }
                   """
                                    ))
    }

    private static func validationExpresion(of node: AttributeSyntax) -> ExprSyntax {
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        guard let uri = arguments?.first(where: { $0.label?.text == "uri" || $0.label == nil })?.expression.description else {
            return ExprSyntax("{ _ in return true }")
        }
        // If uri == "*", skip validation entirely
        if uri == "\"*\"" || uri == "\"/*\"" || uri == "" {
            return ExprSyntax("{ _ in return true }")
        }

        var validations: [ExprSyntax] = ["$0.uri == \(raw: uri)"]

        if let method = arguments?
            .first(where: { $0.label?.text == "method" })?
            .expression
            .description {
            validations.append("$0.method == \(raw: method)")
        }

        var expr = validations[0]
        for part in validations.dropFirst() {
            expr = ExprSyntax("\(expr) && \(part)")
        }

        return ExprSyntax("{ \(expr) }")
    }

    private static func variableExpansion(
        of node: AttributeSyntax,
        providingPeersOf variable: VariableDeclSyntax,
        in context: some MacroExpansionContext,
        validationExpresion: ExprSyntax
    ) throws -> StructuredExpansion? {
        guard let binding = variable.bindings.first,
              let varName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return nil
        }
        if let expansion = serverStubVariableExpansion(varName: varName, validationExpresion: validationExpresion, binding) {
            return expansion
        }
        if let expansion = variableClosureExpansion(of: variable, varName: varName, in: context, validationExpresion: validationExpresion) {
            return expansion
        }
        let stubName = ExprSyntax("_\(raw: varName)Stub()")
        return StructuredExpansion(stubName: stubName,
                                   declaration: DeclSyntax(
                """
                private func \(stubName) -> ServerStub {
                    let resp = self.\(raw: varName)
                    return ServerStub(
                        matchingRequest: \(validationExpresion),
                        returning: resp
                    )
                }
                """
                                   ))
    }

    private static func variableClosureExpansion(
        of variable: VariableDeclSyntax,
        varName: String,
        in context: some MacroExpansionContext,
        validationExpresion: ExprSyntax
    ) -> StructuredExpansion? {
        guard
            let binding = variable.bindings.first,
            let typeAnnotation = binding.typeAnnotation,
            let attributedType = typeAnnotation.type.as(AttributedTypeSyntax.self),
            let functionType = attributedType.baseType.as(FunctionTypeSyntax.self)
        else {
            return nil
        }

        guard
            functionType.parameters.count == 1,
            let parameterType = functionType.parameters.first?.type.as(IdentifierTypeSyntax.self),
            parameterType.name.text == "HTTPRequest"
        else {
            context.diagnose(
                Diagnostic(node: Syntax(functionType.parameters),
                           message: SimpleError(message: "Stub must accept exactly one HTTPRequest parameter."))
            )
            return nil
        }

        guard
            let returnType = functionType.returnClause.type.as(OptionalTypeSyntax.self),
            let memberType = returnType.wrappedType.as(MemberTypeSyntax.self),
            memberType.baseType.as(IdentifierTypeSyntax.self)?.name.text == "ServerStub",
            memberType.name.text == "Response"
        else {
            context.diagnose(
                Diagnostic(node: Syntax(functionType.returnClause),
                           message: SimpleError(message: "Stub must return ServerStub.Response?."))
            )
            return nil
        }
        let stubName = ExprSyntax("_\(raw: varName)Stub()")
        return StructuredExpansion(stubName: stubName,
                                   declaration: DeclSyntax(
                   """
                   private func \(stubName) -> ServerStub {
                       let resp = self.\(raw: varName)
                       return ServerStub(
                           matchingRequest: \(validationExpresion),
                           handler: resp
                       )
                   }
                   """
                                   ))
    }


    struct SimpleError: DiagnosticMessage {
        let message: String

        var diagnosticID: MessageID {
            MessageID(domain: "StubMacro", id: message)
        }

        var severity: DiagnosticSeverity { .error }
    }


    private static func serverStubVariableExpansion(varName: String,
                                                    validationExpresion: ExprSyntax,
                                                    _ binding: PatternBindingSyntax) -> StructuredExpansion? {
        if let typeAnnotation = binding.typeAnnotation?.type,
           let expansion = forbiddenServerStubFunctionExpansion(varName: varName,
                                                                validationExpresion: validationExpresion,
                                                                type: typeAnnotation) {
            return expansion
        }
        if let typeAnnotation = binding.typeAnnotation?.type {
            let typeDescription = typeAnnotation.description
            if typeDescription.contains("ServerStub") {
                return .singleStub(stubName: ExprSyntax("\(raw: varName)"))
            }
        }
        guard let initializer = binding.initializer else {
            return nil
        }
        guard let arrayExpr = initializer.value.as(ArrayExprSyntax.self) else {
            if isExpressionServerStub(initializer.value) {
                return .singleStub(stubName: ExprSyntax("\(raw: varName)"))
            }
            return nil
        }

        if (arrayExpr.elements.contains { element in isExpressionServerStub(element.expression) }) {
            return .collectionStub(stubName: ExprSyntax("\(raw: varName)"))
        }
        return nil
    }

    private static func isExpressionServerStub(_ expr: ExprSyntax) -> Bool {
        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            return isExpressionServerStub(functionCall.calledExpression)
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text.contains("ServerStub") {
                return true
            }
            let declName = memberAccess.declName.baseName.text
            if declName.contains("ServerStub") {
                return true
            }
        }

        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text.contains("ServerStub")
        }
        return false
    }


    private static func forbiddenServerStubFunctionExpansion(varName: String,
                                                             validationExpresion: ExprSyntax,
                                                             type: TypeSyntax) -> StructuredExpansion? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return forbiddenServerStubFunctionExpansion(varName: varName, validationExpresion: validationExpresion, type: attributed.baseType)
        }

        if let optional = type.as(OptionalTypeSyntax.self) {
            return forbiddenServerStubFunctionExpansion(varName: varName, validationExpresion: validationExpresion, type: optional.wrappedType)
        }

        guard let functionType = type.as(FunctionTypeSyntax.self) else {
            return nil
        }

        let hasHTTPRequestParam = functionType.parameters.count == 1 &&
        functionType.parameters.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "HTTPRequest"

        let returnsServerStubResponse = checkReturnType(functionType.returnClause.type)

        guard hasHTTPRequestParam && returnsServerStubResponse else {
            return nil
        }
        let stubName = ExprSyntax("_\(raw: varName)Stub()")
        return StructuredExpansion(stubName: stubName,
                                   declaration: DeclSyntax(
                """
                private func \(stubName) -> ServerStub {
                    let resp = self.\(raw: varName)
                    return ServerStub(
                        matchingRequest: \(validationExpresion),
                        handler: resp
                    )
                }
                """
                                   ))
    }

    private static func checkReturnType(_ type: TypeSyntax) -> Bool {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return checkReturnType(optional.wrappedType)
        }

        if let member = type.as(MemberTypeSyntax.self) {
            let base = member.baseType.as(IdentifierTypeSyntax.self)?.name.text
            let name = member.name.text
            return base == "ServerStub" && name == "Response"
        }
        return false
    }
}
