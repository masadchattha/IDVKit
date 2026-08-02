//
//  IDVLog.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

// Re-exported so any module that imports IDVKitCore gets `Logger` without a
// separate `import OSLog` — the categorized loggers below are the entry point.
@_exported import OSLog

/// IDVKit's logging switch. Silent by default.
///
/// When enabled, the SDK logs to the unified logging system
/// (Console.app, subsystem `dev.idvkit`) — never to files, never to the
/// network. Biometric data, document fields and similarity scores are
/// **never** logged at any level.
///
/// ```swift
/// #if DEBUG
/// IDVLog.isEnabled = true
/// #endif
/// ```
public enum IDVLog {
    /// Enables debug logging for all IDVKit modules. Off by default.
    public static var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set { enabled.withLock { $0 = newValue } }
    }

    private static let enabled = OSAllocatedUnfairLock(initialState: false)
}

// MARK: - SDK-internal categorized loggers (not part of the public API)

extension Logger {
    private static let subsystem = "dev.idvkit"

    /// MRZ scanning and parsing.
    package static let mrz = Logger(subsystem: subsystem, category: "MRZ")
    /// NFC session, APDUs, chip authentication.
    package static let nfc = Logger(subsystem: subsystem, category: "NFC")
    /// Liveness and face matching.
    package static let face = Logger(subsystem: subsystem, category: "Face")
    /// JPEG2000 decoding.
    package static let imaging = Logger(subsystem: subsystem, category: "Imaging")
    /// Flow UI and navigation.
    package static let ui = Logger(subsystem: subsystem, category: "UI")
}

extension Logger {
    /// Logs only when the host app opted in via ``IDVLog/isEnabled``.
    package func idvDebug(_ message: @autoclosure () -> String) {
        guard IDVLog.isEnabled else { return }
        let resolved = message()
        debug("\(resolved, privacy: .public)")
    }

    /// Logs only when the host app opted in via ``IDVLog/isEnabled``.
    package func idvError(_ message: @autoclosure () -> String) {
        guard IDVLog.isEnabled else { return }
        let resolved = message()
        error("\(resolved, privacy: .public)")
    }
}
