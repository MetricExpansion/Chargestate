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
        
        super.init()
        fetchReqCont.delegate = self
        
        if shouldLoadCalendar {
            loadCalendar()
        }
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
        async {
            guard let eventStore = self.eventsStore else { return }
            let cal = Calendar(identifier: .gregorian)
            let datePred = eventStore.predicateForEvents(withStart: Date(), end: cal.date(byAdding: .year, value: 1, to: Date()) ?? Date(), calendars: nil)
            calendarItems = eventStore.events(matching: datePred).filter{ $0.structuredLocation != nil }
            print("EVENTS: ", calendarItems)
            updateItems()
        }
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
    
    
    let container: NSPersistentContainer
    var eventsStore: EKEventStore?

    @Published var items: [ChargeTime] = []
    var calendarItems: [EKEvent] = []
    var manualItems: [Item] = []

    var fetchReqCont: NSFetchedResultsController<Item>
    
    /// Helper stuff
}

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
