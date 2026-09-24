//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Atomics

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Current date formatted cache
///
/// Getting the current date formatted is an expensive operation. This caches the date in the
/// format as detailed in RFC9110 along with the second it was rendered for. Each read checks
/// the current time and renders the date again only when the second has changed, so the value
/// returned always names the second in which it is read.
@available(hummingbird 2.0, *)
final class DateCache: Sendable {
    final class DateContainer: AtomicReference, Sendable {
        let second: Int64
        let date: String

        init(second: Int64) {
            self.second = second
            self.date = Date(timeIntervalSince1970: Double(second)).httpHeader
        }
    }

    let dateContainer: ManagedAtomic<DateContainer>
    let now: @Sendable () -> Date

    /// Initialize DateCache
    /// - Parameter now: Closure returning the current time
    init(now: @escaping @Sendable () -> Date = { Date.now }) {
        self.now = now
        self.dateContainer = .init(.init(second: Self.second(of: now())))
    }

    /// Current date formatted as detailed in RFC9110
    var date: String {
        let second = Self.second(of: self.now())
        let container = self.dateContainer.load(ordering: .acquiring)
        if container.second == second {
            return container.date
        }
        let updated = DateContainer(second: second)
        self.dateContainer.store(updated, ordering: .releasing)
        return updated.date
    }

    static func second(of date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }
}
