
public struct MacroName: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {}
}

@attached(member, names: arbitrary)
public macro MockServer(serverPropertyName: MacroName? = nil) =
#externalMacro(module: "HTTPMockServerMacros", type: "MockServerMacro")

@attached(peer)
public macro Stub() =
#externalMacro(module: "HTTPMockServerMacros", type: "ServerStubMemberMacro")

@attached(peer, names: arbitrary)
public macro Stub(uri: String, method: HTTPMethod? = nil) =
#externalMacro(module: "HTTPMockServerMacros", type: "ServerStubMemberMacro")
