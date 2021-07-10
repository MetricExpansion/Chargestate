//
//  Timeline.swift
//  Chargestate
//
//  Created by Avinash Vakil on 7/9/21.
//

import Foundation
import EventKit

enum TimelineItem: Equatable {
    case manual(Item)
    case calendar(EKEvent)
    case controlPoint(ChargeControlPoint)
    
    func manualItem() -> Item? {
        if case .manual(let item) = self {
            return item
        } else {
            return nil
        }
    }

    var date: Date {
        switch self {
        case .manual(let item):
            return item.timestamp!
        case .calendar(let item):
            return item.startDate
        case .controlPoint(let item):
            return item.date
        }
    }
    
    static func fromChargeTime(_ item: ChargeTime) -> TimelineItem {
        switch item {
        case .manual(let item):
            return .manual(item)
        case .calendar(let item):
            return .calendar(item)
        }
    }
}

extension TimelineItem: Identifiable {
    var id: String {
        switch self {
        case .manual(let item):
            return "\(item.objectID.uriRepresentation())"
        case .calendar(let item):
            return item.calendarItemIdentifier
        case .controlPoint(let item):
            return item.hashValue.formatted()
        }
    }
}

struct TimelineItemSection: Equatable, Identifiable {
    let day: DateComponents
    let items: [TimelineItem]
    var id: DateComponents {
        return day
    }
    var date: Date {
        return Calendar.current.date(from: day)!
    }
    
    @MainActor static func groupedByDateFromAppState(appState: AppState, adjustForDisplay: Bool = false) -> [TimelineItemSection] {
        var items = appState.items.map { TimelineItem.fromChargeTime($0) } + (appState.chargeControlPoints ?? []).map { TimelineItem.controlPoint($0) }
        
        // So that it looks nice on the display, we will "fudge" the charge stop points so that they occur after the charge events.
        if adjustForDisplay {
            items = items.map{ item in
                if case let .controlPoint(item) = item {
                    if item.charging == false {
                        return TimelineItem.controlPoint(ChargeControlPoint(date: item.date.addingTimeInterval(2), chargeLimit: item.chargeLimit, charging: item.charging))
                    }
                }
                return item
            }
        }
        
        items.sort{ $0.date < $1.date }
        let dict = Dictionary(grouping: items, by: { Calendar.current.dateComponents([.day, .month, .year], from: $0.date) })
        let list = dict.map{ k, v in TimelineItemSection(day: k, items: v)}.sorted{ $0.items[0].date < $1.items[0].date }
        return list
    }
}
