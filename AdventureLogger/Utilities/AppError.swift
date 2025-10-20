import Foundation


enum AppError: LocalizedError, Equatable {
    case iCloudUnavailable
    case networkOffline
    case databaseSaveFailed
    case fetchFailed
    case permissionDenied(feature: String)          
    case shareFailed(reason: String)
    case fileIO(message: String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is unavailable. Please sign in and try again."
        case .networkOffline:
            return "You’re offline. We’ll retry when you’re back online."
        case .databaseSaveFailed:
            return "Couldn’t save your changes. Please try again."
        case .fetchFailed:
            return "Couldn’t load your data right now."
        case .permissionDenied(let feature):
            return "\(feature) permission is required. You can enable it in Settings."
        case .shareFailed(let reason):
            return "Couldn’t share this item: \(reason)"
        case .fileIO(let message):
            return "File error: \(message)"
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}
