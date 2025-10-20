import SwiftUI
import Combine

#if canImport(OSLog)
import OSLog
#else
import os
#endif

@MainActor
final class ErrorPresenter: ObservableObject {
    @Published var message: String? = nil
    var onRetry: (() -> Void)?

    private let logger = Logger(subsystem: "AdventureLogger", category: "Error")

    func show(_ error: Error, retry: (() -> Void)? = nil) {
        let desc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let text = desc.isEmpty ? "An error occurred." : desc
        message = text
        onRetry = retry
        logger.error("User-visible error: \(text, privacy: .public)")
    }

    func clear() {
        message = nil
        onRetry = nil
    }
}
