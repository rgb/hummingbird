//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

public import HTTPTypes
public import HummingbirdCore

/// Create rules for routing requests and then create `Responder` that will follow these rules.
///
/// `Router` requires an implementation of  the `on(path:method:use)` functions but because it
/// also conforms to `RouterMethods` it is also possible to call the method specific functions `get`, `put`,
/// `head`, `post` and `patch`.  The route handler closures all return objects conforming to
/// `ResponseGenerator`.  This allows us to support routes which return a multitude of types eg
/// ```
/// router.get("string") { _, _ -> String in
///     return "string"
/// }
/// router.post("status") { _, _ -> HTTPResponse.Status in
///     return .ok
/// }
/// router.data("data") { request, context -> ByteBuffer in
///     return ByteBuffer(string: "buffer")
/// }
/// ```
///
/// The default `Router` setup in `Application` is the `TrieRouter` . This uses a
/// trie to partition all the routes for faster access. It also supports wildcards and parameter extraction
/// ```
/// router.get("user/*", use: anyUser)
/// router.get("user/:id", use: userWithId)
/// ```
/// Both of these match routes which start with "/user" and the next path segment being anything.
/// The second version extracts the path segment out and adds it to `Request.parameters` with the
/// key "id".
@available(hummingbird 2.0, *)
public final class Router<Context: RequestContext>: RouterMethods, HTTPResponderBuilder {
    var trie: RouterPathTrieBuilder<EndpointResponders<Context>>
    public let middlewares: MiddlewareGroup<Context>
    let options: RouterOptions

    public init(context: Context.Type = BasicRequestContext.self, options: RouterOptions = []) {
        self.trie = RouterPathTrieBuilder()
        self.middlewares = .init()
        self.options = options
    }

    /// build responder from router
    public func buildResponder() -> RouterResponder<Context> {
        #if DEBUG
        do {
            try self.validate()
        } catch {
            assertionFailure("\(error)")
        }
        #endif
        if self.options.contains(.autoGenerateHeadEndpoints) {
            // swift-format-ignore: ReplaceForEachWithForLoop
            self.trie.forEach { node in
                node.value?.autoGenerateHeadEndpoint()
            }
        }
        if self.options.contains(.autoGenerateOptionsEndpoints) {
            // this has to run after the HEAD endpoints have been generated, otherwise they
            // will be missing from the `Allow` header
            // swift-format-ignore: ReplaceForEachWithForLoop
            self.trie.forEach { node in
                node.value?.autoGenerateOptionsEndpoint { allow in
                    self.middlewares.constructResponder(finalResponder: OptionsResponder<Context>(allow: allow))
                }
            }
        }
        if self.options.contains(.methodNotAllowed) {
            // this has to run after the HEAD and OPTIONS endpoints have been generated,
            // otherwise they will be missing from the `Allow` header
            // swift-format-ignore: ReplaceForEachWithForLoop
            self.trie.forEach { node in
                node.value?.setMethodNotAllowedResponder { allow in
                    self.middlewares.constructResponder(finalResponder: MethodNotAllowedResponder<Context>(allow: allow))
                }
            }
        }
        return .init(
            context: Context.self,
            trie: self.trie,
            options: self.options,
            notFoundResponder: self.middlewares.constructResponder(finalResponder: NotFoundResponder<Context>())
        )
    }

    /// Add responder to call when path and method are matched
    ///
    /// - Parameters:
    ///   - path: Path to match
    ///   - method: Request method to match
    ///   - responder: Responder to call if match is made
    @discardableResult public func on<Responder: HTTPResponder>(
        _ path: RouterPath,
        method: HTTPRequest.Method,
        responder: Responder
    ) -> Self where Responder.Context == Context {
        var path = path
        if self.options.contains(.caseInsensitive) {
            path = path.lowercased()
        }
        self.trie.addEntry(path, value: EndpointResponders(path: path)) { node in
            node.value!.addResponder(for: method, responder: self.middlewares.constructResponder(finalResponder: responder))
        }
        return self
    }

    /// Add middleware to Router
    ///
    /// This middleware will only be applied to endpoints added after this call.
    /// - Parameter middleware: Middleware we are adding
    @discardableResult public func add(middleware: any MiddlewareProtocol<Request, Response, Context>) -> Self {
        self.middlewares.add(middleware)
        return self
    }
}

/// Responder that return a not found error
struct NotFoundResponder<Context: RequestContext>: HTTPResponder {
    func respond(to request: Request, context: Context) throws -> Response {
        context.coreContext.endpointPath.value = "NotFound"
        throw HTTPError(.notFound)
    }
}

/// Responder that returns a method not allowed error, along with the list of methods the
/// endpoint does support
struct MethodNotAllowedResponder<Context: RequestContext>: HTTPResponder {
    /// Value for the `Allow` header, required in a 405 response by RFC 9110 § 15.5.6
    let allow: String

    func respond(to request: Request, context: Context) throws -> Response {
        context.coreContext.endpointPath.value = "MethodNotAllowed"
        throw HTTPError(.methodNotAllowed, headers: [.allow: self.allow])
    }
}

/// Responder that returns the methods an endpoint supports, for an OPTIONS request
///
/// RFC 9110 § 9.3.7 defines the response to OPTIONS as communicating the options available
/// for a resource. As there is no response content, this returns 204 (No Content)
struct OptionsResponder<Context: RequestContext>: HTTPResponder {
    /// Value for the `Allow` header, listing the methods this endpoint supports
    let allow: String

    func respond(to request: Request, context: Context) -> Response {
        Response(status: .noContent, headers: [.allow: self.allow])
    }
}

/// A type that has a single method to build a HTTPResponder
public protocol HTTPResponderBuilder {
    associatedtype Responder: HTTPResponder
    /// build a responder
    func buildResponder() -> Responder
}

/// Router Options
public struct RouterOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Router path comparisons will be case insensitive
    public static var caseInsensitive: Self { .init(rawValue: 1 << 0) }
    /// For every GET request that does not have a HEAD request, auto generate the HEAD request
    public static var autoGenerateHeadEndpoints: Self { .init(rawValue: 1 << 1) }
    /// For every endpoint that does not have an OPTIONS request, auto generate one returning
    /// the methods that endpoint supports in the `Allow` header
    public static var autoGenerateOptionsEndpoints: Self { .init(rawValue: 1 << 2) }
    /// Respond to a request whose path matches a route but whose method does not with
    /// 405 (Method Not Allowed) instead of 404 (Not Found)
    public static var methodNotAllowed: Self { .init(rawValue: 1 << 3) }
}
