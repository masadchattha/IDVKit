//
//  IDVNFCSessionSupportTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 14/10/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
@testable import IDVKitNFC
import Testing

struct NFCSessionSupportTests {
    @Test func secondConcurrentReadIsRefusedUntilTheFirstSessionEnds() throws {
        let sessionGuard = IDVNFCSessionGuard()
        try sessionGuard.acquire() // first read

        #expect(throws: IDVError.nfcBusy) { try sessionGuard.acquire() } // second read, immediately

        sessionGuard.release() // the first session's didInvalidateWithError
        #expect(throws: Never.self) { try sessionGuard.acquire() }
    }

    @Test func readReturnsOnceInvalidationFires() async {
        let waiter = IDVInvalidationWaiter()
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            waiter.signal() // didInvalidateWithError
        }
        // A long cap, so returning early can only mean the signal woke the waiter
        // (wall time is unreliable here: the suite runs alongside -Onone EC math).
        let start = Date.now
        let signaled = await waiter.wait(cap: 30)
        #expect(signaled)
        #expect(Date.now.timeIntervalSince(start) < 30)
    }

    @Test func readGivesUpWaitingAfterTheCap() async {
        let waiter = IDVInvalidationWaiter()
        let start = Date.now
        let signaled = await waiter.wait(cap: 0.2)
        #expect(!signaled)
        #expect(Date.now.timeIntervalSince(start) >= 0.2)
    }

    @Test func signalBeforeWaitReturnsImmediately() async {
        let waiter = IDVInvalidationWaiter()
        waiter.signal()
        #expect(await waiter.wait(cap: 2))
    }

    #if canImport(CoreNFC)
        @Test func systemBusyAtStartIsRetriedExactlyOnce() {
            // 203 "System resource unavailable" before any tag connected → one retry.
            #expect(IDVNFCSession.shouldRetryBegin(after: .nfcBusy, attempt: 1, tagConnected: false))
            // Then it surfaces as nfcBusy, not a timeout.
            #expect(!IDVNFCSession.shouldRetryBegin(after: .nfcBusy, attempt: 2, tagConnected: false))
            // A 203 after a tag was connected is a different failure, not a busy start.
            #expect(!IDVNFCSession.shouldRetryBegin(after: .nfcBusy, attempt: 1, tagConnected: true))
            #expect(!IDVNFCSession.shouldRetryBegin(after: .nfcUserCancelled, attempt: 1, tagConnected: false))
        }

        @Test func cancelRightAfterAGlitchIsNotTheUser() {
            // 46 ms after a dropped tag nobody has tapped Cancel: that is iOS closing the session.
            #expect(IDVNFCSession.friendlyError(code: 200, recentGlitch: true) == .nfcTagConnectionLost)
            #expect(IDVNFCSession.friendlyError(code: 200, recentGlitch: false) == .nfcUserCancelled)
        }

        @Test func everyCoreNFCCodeMapsToAFriendlyError() {
            let expected: [Int: IDVError] = [
                100: .nfcTagConnectionLost, 101: .nfcTagConnectionLost, 102: .nfcTagConnectionLost,
                103: .nfcTagConnectionLost, 104: .nfcTagConnectionLost, 105: .nfcTagConnectionLost,
                201: .nfcSessionTimeout, 202: .nfcTagConnectionLost, 203: .nfcBusy
            ]
            for (code, error) in expected {
                #expect(IDVNFCSession.friendlyError(code: code, recentGlitch: false) == error, "code \(code)")
            }
            // Nothing ever surfaces CoreNFC's own wording.
            for code in [100, 101, 102, 103, 104, 105, 200, 201, 202, 203, 204, 999] {
                let text = IDVNFCSession.friendlyError(code: code, recentGlitch: false).errorDescription ?? ""
                #expect(!text.contains("Session invalidated"), "code \(code)")
                #expect(!text.contains("System resource"), "code \(code)")
                #expect(!text.contains("Tag connection lost"), "code \(code)")
            }
        }
    #endif
}
