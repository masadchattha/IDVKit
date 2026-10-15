//
//  IDVNFCSessionSupport.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 14/10/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore

/// Process-wide "one NFC session at a time" guard.
///
/// Starting a second `NFCTagReaderSession` kills the running one (iOS reports
/// it as user-cancelled) and the newcomer then fails with "System resource
/// unavailable". `acquire()` is taken before CoreNFC is touched and released only
/// once the old session's invalidation callback has fired — not when `read()`
/// returns — so a quick re-tap can never collide with a session still tearing down.
final class IDVNFCSessionGuard: @unchecked Sendable {
    static let shared = IDVNFCSessionGuard()

    private let active = OSAllocatedUnfairLock(initialState: false)

    /// - Throws: ``IDVError/nfcBusy`` if a session is already active.
    func acquire() throws {
        try active.withLock { isActive in
            if isActive {
                throw IDVError.nfcBusy
            }
            isActive = true
        }
    }

    func release() {
        active.withLock { $0 = false }
    }
}

/// Lets `read()` wait for the session's invalidation callback (the system sheet
/// is gone and CoreNFC has torn down) before returning, capped so a missing
/// callback can't hang the caller. Signal and timeout race for one waiter.
final class IDVInvalidationWaiter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var fired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func signal() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            fired = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }

    /// - Returns: `true` when the signal arrived, `false` when `cap` elapsed first.
    func wait(cap: TimeInterval) async -> Bool {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let alreadyFired: Bool = lock.withLock {
                if fired {
                    return true
                }
                continuation = waiter
                return false
            }
            if alreadyFired {
                waiter.resume()
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(cap))
                guard let self else { return }
                let pending: CheckedContinuation<Void, Never>? = lock.withLock {
                    defer { continuation = nil }
                    return continuation
                }
                pending?.resume()
            }
        }
        return lock.withLock { fired }
    }
}
