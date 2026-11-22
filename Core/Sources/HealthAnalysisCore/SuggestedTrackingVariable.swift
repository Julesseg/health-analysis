import Foundation

public enum SuggestedTrackingVariable: String, CaseIterable, Codable, Identifiable, Sendable {
    case caffeine
    case alcohol
    case medicationIntake
    case stress
    case energy
    case workoutDuration
    case runningDuration

    public enum Definition: Sendable {
        case quantity(unit: String, defaultValue: Decimal)
        case count
        case rating
    }

    public var id: Self { self }

    public var definition: Definition {
        switch self {
        case .caffeine: .quantity(unit: "mg", defaultValue: 0)
        case .alcohol, .medicationIntake: .count
        case .stress, .energy: .rating
        case .workoutDuration, .runningDuration: .quantity(unit: "min", defaultValue: 0)
        }
    }

    func matches(name: String) -> Bool {
        let aliases: [String] = switch self {
        case .caffeine: ["caffeine", "caffeine intake"]
        case .alcohol: ["alcohol", "alcohol drinks"]
        case .medicationIntake: ["medication", "medication intake", "medication doses"]
        case .stress: ["stress", "stress level"]
        case .energy: ["energy", "energy level"]
        case .workoutDuration: ["activity", "exercise", "exercise log", "workout duration"]
        case .runningDuration: ["running", "running duration", "running distance"]
        }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases.contains(normalized)
    }
}
