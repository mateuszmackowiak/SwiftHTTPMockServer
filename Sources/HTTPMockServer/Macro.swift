@attached(member, names: named(server), named(init), named(deinit))
public macro MockServer() =
#externalMacro(module: "HTTPMockServerMacros", type: "MockServerMacro")


@attached(peer)
public macro Stub() =
#externalMacro(module: "HTTPMockServerMacros", type: "ServerStubMemberMacro")
