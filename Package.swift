// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CampusScheduleCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CampusScheduleCore", targets: ["CampusScheduleCore"])],
    targets: [
        .target(name: "CampusScheduleCore", path: "Shared", exclude: ["ReminderBoard.swift", "WidgetBoard.swift"],
            sources: ["Models.swift", "Homework.swift", "Pomodoro.swift", "PetPlacement.swift", "LegacyReviews.swift", "Modules.swift", "ReminderEngine.swift", "CalendarPlacement.swift", "CalendarTimeScale.swift", "WeekCalendarLayout.swift", "WorkSummary.swift", "SharedRepository.swift", "ICalendarParser.swift"]),
        .testTarget(name: "CampusScheduleCoreTests", dependencies: ["CampusScheduleCore"], path: "Tests")
    ]
)
