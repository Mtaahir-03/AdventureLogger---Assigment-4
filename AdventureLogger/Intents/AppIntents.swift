//
//  AppIntents.swift
//  AdventureLogger
//
//  Siri and Shortcuts integration
//

import AppIntents
import CoreLocation
import CoreData
import WidgetKit
import MapKit

// MARK: - App Shortcuts Provider

struct AdventureLoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogCurrentLocationIntent(),
            phrases: [
                "Log my current location in \(.applicationName)",
                "Add current location to \(.applicationName)",
                "Save where I am in \(.applicationName)"
            ],
            shortTitle: "Log Current Location",
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: AddPlaceIntent(),
            phrases: [
                "Add a place to \(.applicationName)",
                "Create adventure in \(.applicationName)",
                "Log a new place in \(.applicationName)"
            ],
            shortTitle: "Add Place",
            systemImageName: "plus.circle.fill"
        )
    }
}

// MARK: - Log Current Location Intent

struct LogCurrentLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Current Location"
    static var description = IntentDescription("Saves your current location as a new adventure")

    @Parameter(title: "Place Name", description: "Name for this location")
    var placeName: String?

    @Parameter(title: "Category", default: .activity)
    var category: PlaceCategory

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let locationManager = CLLocationManager()

        // Check authorization
        guard locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            throw IntentLocationError.notAuthorized
        }

        // Get current location
        guard let location = locationManager.location else {
            throw IntentLocationError.locationUnavailable
        }

        // Save to Core Data
        let context = PersistenceController.shared.container.viewContext
        let newPlace = Place(context: context)
        newPlace.id = UUID()
        newPlace.name = placeName ?? "Current Location"
        newPlace.category = category.rawValue
        newPlace.latitude = location.coordinate.latitude
        newPlace.longitude = location.coordinate.longitude
        newPlace.isVisited = false
        newPlace.createdAt = Date()
        newPlace.updatedAt = Date()

        // Reverse geocode to get address
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            var addressParts: [String] = []
            if let name = placemark.name { addressParts.append(name) }
            if let locality = placemark.locality { addressParts.append(locality) }
            if let country = placemark.country { addressParts.append(country) }
            newPlace.address = addressParts.joined(separator: ", ")
        }

        try context.save()

        // Update widget
        updateWidget(place: newPlace)

        return .result(
            dialog: IntentDialog("Added \(placeName ?? "your current location") to AdventureLogger!")
        )
    }

    private func updateWidget(place: Place) {
        let appGroupID = "group.muhammedsa-dmahomed.AdventureLogger"
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let snapshot: [String: Any] = [
            "title": place.name ?? "New Adventure",
            "subtitle": place.category ?? "",
            "date": ISO8601DateFormatter().string(from: place.createdAt ?? Date()),
            "metric": place.address ?? "\(place.latitude), \(place.longitude)"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: snapshot) {
            defaults.set(data, forKey: "widget.latestAdventure")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Add Place Intent

struct AddPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Place"
    static var description = IntentDescription("Adds a new place to your adventure list")

    @Parameter(title: "Place Name", requestValueDialog: "What place would you like to add?")
    var placeName: String

    @Parameter(title: "Category", default: .activity)
    var category: PlaceCategory

    @Parameter(title: "Already Visited", default: false)
    var isVisited: Bool

    @Parameter(title: "Rating (1-5)", default: 0)
    var rating: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Validate input
        guard !placeName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw IntentValidationError.invalidInput("Place name cannot be empty")
        }

        // Search for the place using MapKit
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = placeName

        let search = MKLocalSearch(request: searchRequest)
        let response = try? await search.start()

        // Save to Core Data
        let context = PersistenceController.shared.container.viewContext
        let newPlace = Place(context: context)
        newPlace.id = UUID()
        newPlace.name = placeName
        newPlace.category = category.rawValue
        newPlace.isVisited = isVisited
        newPlace.rating = Int16(min(max(rating, 0), 5))
        newPlace.createdAt = Date()
        newPlace.updatedAt = Date()

        // If we found location data, use it
        if let mapItem = response?.mapItems.first {
            newPlace.latitude = mapItem.placemark.coordinate.latitude
            newPlace.longitude = mapItem.placemark.coordinate.longitude

            // Build address from placemark
            var addressParts: [String] = []
            if let name = mapItem.name { addressParts.append(name) }
            if let thoroughfare = mapItem.placemark.thoroughfare {
                addressParts.append(thoroughfare)
            }
            if let locality = mapItem.placemark.locality {
                addressParts.append(locality)
            }
            if let country = mapItem.placemark.country {
                addressParts.append(country)
            }
            newPlace.address = addressParts.joined(separator: ", ")
        } else {
            // No location found - set defaults
            newPlace.latitude = 0.0
            newPlace.longitude = 0.0
        }

        if isVisited {
            newPlace.visitedDate = Date()
        }

        try context.save()

        // Update widget
        updateWidget(place: newPlace)

        let locationInfo = (newPlace.latitude != 0.0 && newPlace.longitude != 0.0)
            ? " Location pinned on map."
            : " (Location not found - you can add it manually later)"

        let message = isVisited
            ? "Added \(placeName) and marked as visited!\(locationInfo)"
            : "Added \(placeName) to your bucket list!\(locationInfo)"

        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    private func updateWidget(place: Place) {
        let appGroupID = "group.muhammedsa-dmahomed.AdventureLogger"
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let snapshot: [String: Any] = [
            "title": place.name ?? "New Adventure",
            "subtitle": place.category ?? "",
            "date": ISO8601DateFormatter().string(from: place.createdAt ?? Date()),
            "metric": place.isVisited ? "Visited" : "Bucket List"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: snapshot) {
            defaults.set(data, forKey: "widget.latestAdventure")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Supporting Types

enum PlaceCategory: String, AppEnum {
    case beach = "Beach"
    case hike = "Hike"
    case activity = "Activity"
    case restaurant = "Restaurant"
    case placeOfWorship = "Place of Worship"
    case other = "Other"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")

    static var caseDisplayRepresentations: [PlaceCategory: DisplayRepresentation] {
        [
            .beach: "Beach",
            .hike: "Hike",
            .activity: "Activity",
            .restaurant: "Restaurant",
            .placeOfWorship: "Place of Worship",
            .other: "Other"
        ]
    }
}

enum IntentLocationError: Error, CustomLocalizedStringResourceConvertible {
    case notAuthorized
    case locationUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAuthorized:
            return "Location access not authorized. Please enable in Settings."
        case .locationUnavailable:
            return "Unable to determine your current location. Please try again."
        }
    }
}

enum IntentValidationError: Error, CustomLocalizedStringResourceConvertible {
    case invalidInput(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidInput(let message):
            return LocalizedStringResource(stringLiteral: message)
        }
    }
}
