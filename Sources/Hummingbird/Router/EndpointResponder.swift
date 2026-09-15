//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

public import HTTPTypes

/// Stores endpoint responders for each HTTP method
@available(hummingbird 2.0, *)
@usableFromInline
struct EndpointResponders<Context>: Sendable {
    init(path: RouterPath) {
        self.path = path
        self.methods = [:]
        self.methodNotAllowedResponder = nil
    }

    /// Return the responder to call for a request method
    ///
    /// Methods this endpoint has no responder for fall back to ``methodNotAllowedResponder``,
    /// which is nil unless the router was built with ``RouterOptions/methodNotAllowed``. When
    /// it is nil this returns nil and the router reports the request as not found.
    @inlinable
    public func getResponder(for method: __shared HTTPRequest.Method) -> (any HTTPResponder<Context>)? {
        self.methods[method] ?? self.methodNotAllowedResponder
    }

    mutating func addResponder(for method: HTTPRequest.Method, responder: any HTTPResponder<Context>) {
        guard self.methods[method] == nil else {
            preconditionFailure("\(method.rawValue) already has a handler")
        }
        self.methods[method] = responder
    }

    /// Set the responder used for any method this endpoint has no responder for
    ///
    /// The builder is passed the value for the `Allow` header, ie the list of methods this
    /// endpoint does have responders for. Call this after all responders have been added.
    mutating func setMethodNotAllowedResponder(_ build: (_ allow: String) -> any HTTPResponder<Context>) {
        self.methodNotAllowedResponder = build(self.allowHeaderValue)
    }

    /// Comma separated list of the methods this endpoint supports, for the `Allow` header.
    /// RFC 9110 § 15.5.6 requires this header in a 405 response and § 9.3.7 recommends it in
    /// a response to OPTIONS
    var allowHeaderValue: String {
        Self.allowHeaderValue(for: self.methods.keys)
    }

    static func allowHeaderValue(for methods: some Collection<HTTPRequest.Method>) -> String {
        methods.map(\.rawValue).sorted().joined(separator: ", ")
    }

    mutating func autoGenerateHeadEndpoint() {
        if self.methods[.head] == nil, let get = methods[.get] {
            self.methods[.head] = CallbackResponder { request, context in
                let response = try await get.respond(to: request, context: context)
                return response.createHeadResponse()
            }
        }
    }

    /// Generate an OPTIONS endpoint for this path, unless one has been added already
    ///
    /// The builder is passed the value for the `Allow` header. Call this after all responders
    /// have been added, so they are all listed.
    mutating func autoGenerateOptionsEndpoint(_ build: (_ allow: String) -> any HTTPResponder<Context>) {
        guard self.methods[.options] == nil else { return }
        // the endpoint we are about to add answers OPTIONS, so include it in its own list
        var methods = Set(self.methods.keys)
        methods.insert(.options)
        self.methods[.options] = build(Self.allowHeaderValue(for: methods))
    }

    @usableFromInline
    var methods: [HTTPRequest.Method: any HTTPResponder<Context>]

    /// Responder used for any method not in ``methods``, ie the default for this endpoint.
    /// Only set if the router was built with the ``RouterOptions/methodNotAllowed`` option
    @usableFromInline
    var methodNotAllowedResponder: (any HTTPResponder<Context>)?

    @usableFromInline
    var path: RouterPath
}
