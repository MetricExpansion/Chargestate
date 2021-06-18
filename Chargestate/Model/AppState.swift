//
//  ChargeController.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import Foundation
import CoreData
import EventKit
import Combine
import KeychainSwift

// MARK: AppState

/// A model for the entire app state.
@MainActor
class AppState: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    /// Preview struct used for SwiftUI. Contains 10 sample items.
    static var preview: AppState {
        let result = AppState(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }

    init(inMemory: Bool = false, loadCalendar shouldLoadCalendar: Bool = false) {
        /// Setup persistent container.
        container = NSPersistentContainer(name: "Chargestate")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true

        let fetchReq = NSFetchRequest<Item>(entityName: "Item")
        fetchReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        self.fetchReqCont = NSFetchedResultsController(
            fetchRequest: fetchReq,
            managedObjectContext: container.viewContext,
            sectionNameKeyPath: nil, cacheName: nil)
        
        try! fetchReqCont.performFetch()
        manualItems = fetchReqCont.fetchedObjects ?? []
        
        self.teslaApi = TeslaSession(token: keychain.get("teslafi_api_token"))
        
        self.userConfig = UserConfig(
            chargeRate: UserDefaults.standard.optionalDouble(forKey: "userConfig_chargeRate") ?? 0.04,
            idleChargeLevel: UserDefaults.standard.optionalDouble(forKey: "userConfig_idleChargeLevel") ?? 0.80,
            travelChargeLevel: UserDefaults.standard.optionalDouble(forKey: "userConfig_travelChargeLevel") ?? 0.90)
        
        super.init()
        fetchReqCont.delegate = self
        teslaApiSubscription = self.teslaApi.$token.dropFirst().sink {  [weak self] newValue in
            if let newValue = newValue {
                self?.keychain.set(newValue, forKey: "teslafi_api_token", withAccess: .accessibleAfterFirstUnlock)
            } else {
                self?.keychain.delete("teslafi_api_token")
            }
        }
        userConfigSubscription = $userConfig.sink{ v in
            print("New UserSetting: \(v)")
        }


        if shouldLoadCalendar {
            loadCalendar()
        }
        
        updateItems()
    }
    
    /// Calendar stuff
    func loadCalendar() {
        self.eventsStore = EKEventStore()
        eventsStore?.requestAccess(to: .event) { granted, error in
            guard let eventStore = self.eventsStore else { return }
            if !granted {
                async {
                    self.eventsStore = nil
                }
            } else {
                // Configure calendar stuff
                async {
                    NotificationCenter.default.addObserver(self, selector: #selector(self.updateEvents), name: .EKEventStoreChanged, object: eventStore)
                    self.updateEvents()
                }
            }
        }
    }
    
    @objc func updateEvents() {
        asyncDetached {
            guard let eventStore = await self.eventsStore else { return }
            let cal = Calendar(identifier: .gregorian)
            let datePred = eventStore.predicateForEvents(withStart: Date(), end: cal.date(byAdding: .month, value: 1, to: Date()) ?? Date(), calendars: nil)
            await self.setCalendarItems(eventStore.events(matching: datePred).filter{ $0.structuredLocation != nil })
            await print("EVENTS: ", calendarItems)
            await updateItems()
        }
    }
    
    fileprivate func setCalendarItems(_ items: [EKEvent]) {
        self.calendarItems = items
    }
    
    /// Core Data Store stuff
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        async {
            manualItems = fetchReqCont.fetchedObjects ?? []
            updateItems()
        }
    }


    func add() {
        async {
            await container.viewContext.perform {
                let newItem = Item(context: self.container.viewContext)
                let maxDiff = 24*60*60*14.0
                newItem.timestamp = Date().addingTimeInterval(Double.random(in: 0.0...maxDiff))
                try? self.container.viewContext.save()
            }
        }
    }
    
    func add(date: Date) {
        async {
            await container.viewContext.perform {
                let newItem = Item(context: self.container.viewContext)
                newItem.timestamp = date
                try? self.container.viewContext.save()
            }
        }
    }
    
    /// Algorithm stuff
    func updateItems() {
        var items: [ChargeTime] = calendarItems.map{ .calendar($0) } + manualItems.map{ .manual($0) }
        items.sort{ $0.date < $1.date }
        self.items = items
    }
    
    var itemsGroupedByDate: [ChargeTimeSection] {
        let dict = Dictionary(grouping: items, by: { Calendar.current.dateComponents([.day, .month, .year], from: $0.date) })
        let list = dict.map{ k, v in ChargeTimeSection(day: k, chargeTimes: v)}.sorted{ $0.chargeTimes[0].date < $1.chargeTimes[0].date }
        return list
    }
    
    var chargeControlRanges: [DateInterval]? {
        let idleToTravelTime = (userConfig.travelChargeLevel - userConfig.idleChargeLevel) / (userConfig.chargeRate) * 60 * 60
        if idleToTravelTime < 0 { return nil }
        let intervals = items.map{ $0.date }.map{ DateInterval(start: $0.addingTimeInterval(-idleToTravelTime), end: $0) }
        var timepoints = intervals.map{ $0.start.addingTimeInterval(-1) } + intervals.map{ $0.start.addingTimeInterval(1) } +
                         intervals.map{ $0.end.addingTimeInterval(-1) } + intervals.map{ $0.end.addingTimeInterval(1) }
        timepoints.sort()
        let timepointLoadings = timepoints.map{ time in (time, intervals.filter{ date in date.contains(time) }.count) }
        let controlPoints = timepointLoadings
            .split{ $0.1 == 0 }
            .filter{ !$0.isEmpty }
            .map{ DateInterval(start: $0.first!.0, end: $0.last!.0) }
        return controlPoints
    }

    var chargeControlPoints: [ChargeControlPoint]? {
        if chargeControlRanges == nil { return nil }
        return chargeControlRanges!
            .map{ [ChargeControlPoint(date: $0.start, chargeLimit: userConfig.travelChargeLevel, charging: true), ChargeControlPoint(date: $0.end, chargeLimit: userConfig.idleChargeLevel, charging: false)] }
            .joined()
            .map{ $0 }
    }
    
    let keychain: KeychainSwift = {
        let k = KeychainSwift(keyPrefix: "AppState_")
        k.synchronizable = true
        return k
    }()
    
    let container: NSPersistentContainer
    var eventsStore: EKEventStore?
    let teslaApi: TeslaSession
    var teslaApiSubscription: AnyCancellable?

    @Published var items: [ChargeTime] = []
    var calendarItems: [EKEvent] = []
    var manualItems: [Item] = []

    var fetchReqCont: NSFetchedResultsController<Item>
    
    /// Helper stuff
    @Published var userConfig: UserConfig
    var userConfigSubscription: AnyCancellable?
}

// MARK: ChargeControlPoint


struct ChargeControlPoint {
    let date: Date
    let chargeLimit: Double
    let charging: Bool
}

// MARK: ChargeTime

enum ChargeTime: Equatable {
    case manual(Item)
    case calendar(EKEvent)
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
        }
    }
}

extension ChargeTime: Identifiable {
    var id: String {
        switch self {
        case .manual(let item):
            return "\(item.objectID.uriRepresentation())"
        case .calendar(let item):
            return item.calendarItemIdentifier
        }
    }
}

// MARK: ChargeTimeSection

struct ChargeTimeSection: Equatable, Identifiable {
    let day: DateComponents
    let chargeTimes: [ChargeTime]
    var id: DateComponents {
        return day
    }
    var date: Date {
        return Calendar.current.date(from: day)!
    }

}

// MARK: UserConfig

struct UserConfig: Codable {
    static let defaultValues = UserConfig(chargeRate: 0.04, idleChargeLevel: 0.80, travelChargeLevel: 0.90)
    
    var chargeRate: Double
    var idleChargeLevel: Double
    var travelChargeLevel: Double
}

// MARK: Extension to UserDefaults

extension UserDefaults {
    func optionalDouble(forKey: String) -> Double? {
        let v = self.double(forKey: forKey)
        if v == 0 { return nil } else { return v }
    }
}