//
//  RelativeSongDate.swift
//  finpro
//

import Foundation

nonisolated enum RelativeSongDate {
    static func text(for date: Date, relativeTo now: Date = Date(),
                     calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                            to: calendar.startOfDay(for: date)).day
        switch days {
        case -1: return "Yesterday"
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let format = DateFormatter()
            format.locale = locale
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.dateStyle = .medium
            format.timeStyle = .none
            return format.string(from: date)
        }
    }
}
