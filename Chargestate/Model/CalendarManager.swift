//
//  CalendarManager.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/28/21.
//

import Foundation
import EventKit

class CalendarManager {
    var eventsStore: EKEventStore
    var accessGranted: Bool
    let cal = Calendar(identifier: .gregorian)

    init() {
        self.eventsStore = EKEventStore()
        self.accessGranted = false
    }
    
    fileprivate func ensureAccess() async throws {
        if !accessGranted {
            accessGranted = try await eventsStore.requestAccess(to: .event)
        }
    }
    
    func getCalendarEvents(calendars: [EKCalendar]?) async -> [EKEvent]? {
        do {
            try await ensureAccess()
        } catch {
            print("Calendar access not possible: \(error)")
            return nil
        }
        if calendars?.isEmpty ?? false {
            return []
        }
        let datePred = eventsStore.predicateForEvents(withStart: Date(), end: cal.date(byAdding: .month, value: 1, to: Date()) ?? Date(), calendars: calendars)
        let matchingEvents = eventsStore.events(matching: datePred).filter{ $0.structuredLocation != nil }
        return matchingEvents
    }
    
    func getCalendarEvents(calendars: [String]?) async -> [EKEvent]? {
        if let calendars = calendars {
            return await getCalendarEvents(calendars: getCalendars(withIds: calendars))
        } else {
            let x: [EKCalendar]? = nil
            return await getCalendarEvents(calendars: x)
        }
    }
    
    func getCalendars() async -> [EKCalendar]? {
        do {
            try await ensureAccess()
        } catch {
            print("Calendar access not possible: \(error)")
            return nil
        }
        return eventsStore.calendars(for: .event)
    }
    
    func getCalendars(withIds ids: [String]) async -> [EKCalendar]? {
        do {
            try await ensureAccess()
        } catch {
            print("Calendar access not possible: \(error)")
            return nil
        }
        return ids.compactMap{ eventsStore.calendar(withIdentifier: $0) }
    }
    
    func getCalendarSequence() -> some AsyncSequence {
        return NotificationCenter.default.notifications(named: .EKEventStoreChanged, object: eventsStore)
    }
}
