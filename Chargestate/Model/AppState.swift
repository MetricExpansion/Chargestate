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

    init(inMemory: Bool = false) {
        let decoder = JSONDecoder()
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
        let cutoff = Date().addingTimeInterval(-60*60)
        fetchReq.predicate = NSPredicate(format: "timestamp > %@", cutoff as NSDate)
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
        
        if let data = UserDefaults.standard.data(forKey: "aws_coded"), let aws = try? decoder.decode(AWSAPI.self, from: data) {
            self.aws = aws
        } else {
            self.aws = AWSAPI()
        }
        
        if let data = UserDefaults.standard.data(forKey: "schedule_submission_status"), let status = try? decoder.decode(ScheduleStatus.self, from: data) {
            self.awsSubscribeStatus = status
        }
        
        if let data = UserDefaults.standard.data(forKey: "enabled_calendars") {
            enabledCalendars = (try? decoder.decode([String].self, from: data)) ?? []
        } else {
            enabledCalendars = []
        }

        
        self.calendarManager = CalendarManager()

        super.init()
        fetchReqCont.delegate = self
        let teslaApiKeyPublisher = self.teslaApi.$token
        teslaApiSubscription = teslaApiKeyPublisher.dropFirst().sink {  [weak self] newValue in
            if let newValue = newValue {
                self?.keychain.set(newValue, forKey: "teslafi_api_token", withAccess: .accessibleAfterFirstUnlock)
            } else {
                self?.keychain.delete("teslafi_api_token")
            }
        }
        
        userConfigSubscription = $userConfig.dropFirst().sink{ v in
            print("New UserSetting: \(v)")
            UserDefaults.standard.set(v.chargeRate, forKey: "userConfig_chargeRate")
            UserDefaults.standard.set(v.idleChargeLevel, forKey: "userConfig_idleChargeLevel")
            UserDefaults.standard.set(v.travelChargeLevel, forKey: "userConfig_travelChargeLevel")
        }
        
        calendarUpdateTask = asyncDetached(priority: .background) { [weak self] in
            await self?.setCalendarItems(await calendarManager.getCalendarEvents(calendars: self?.enabledCalendars) ?? [])
            let seq = await calendarManager.getCalendarSequence();
            do {
                for try await _ in seq {
                    await self?.setCalendarItems(await calendarManager.getCalendarEvents(calendars: self?.enabledCalendars) ?? [])
                }
            } catch {
                print("Calendar update loop has failed \(error)")
            }
        }
        
        let scheduleRequestStream = self.$items
            .receive(on: RunLoop.main)
            .combineLatest(self.$userConfig, teslaApiKeyPublisher)
            .drop(while: { _ in self.calendarItems == nil })
            .share()
        
        subscriptions.append(scheduleRequestStream.debounce(for: .seconds(5), scheduler: RunLoop.main).sink{ [weak self] x in
            print("Checking to see if new schedule needs to be sent.")
            async { [weak self] in
                let result = await self?.submitSchedule()
                switch result {
                case .waiting:
                    fallthrough
                case .ignoredDueToIdempotency:
                    fallthrough
                case .ignoredDueToMissingCalendarInfo:
                    fallthrough
                case .ignoredDueToMissingTeslaFiToken:
                    fallthrough
                case .ignoredDueToInvalidChargePoints:
                    fallthrough
                case .ignoredDueToMissingAPNSEndpoint:
                    print("Schedule request ignored: \(String(describing: result!))")
                case .requestFailed(let error):
                    print("Schedule request failed: \(error)")
                case .scheduled:
                    print("Schedule request was accepted.")
                case .none:
                    print("Schedule request ignored because AppState instance is missing. This should not happen.")
                }
                self?.awsSubscribeStatus = result
            }
        })
        
        subscriptions.append(scheduleRequestStream.dropFirst().sink { [weak self] _ in
            self?.awsSubscribeStatus = .waiting
        })
        
        let encoder = JSONEncoder()
        awsSubscribeStatusSubscription = self.$awsSubscribeStatus.sink { v in UserDefaults.standard.set(try? encoder.encode(v), forKey: "schedule_submission_status") }

        updateItems()
        
        self.cleanupOldManualItems()
    }
    
    deinit {
        calendarUpdateTask?.cancel()
    }
    
    func saveData() {
        aws.saveTo(userDefaults: UserDefaults.standard, key: "aws_coded")
    }
    
    /// Calendar stuff
    func loadCalendar() async {
        self.setCalendarItems(await calendarManager.getCalendarEvents(calendars: self.enabledCalendars) ?? [])
    }
    
    fileprivate func setCalendarItems(_ items: [EKEvent]) {
        self.calendarItems = items
        updateItems()
    }
    
    func cleanupOldManualItems() {
        let fetchReq = NSFetchRequest<Item>(entityName: "Item")
        fetchReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        let cutoff = Date().addingTimeInterval(-60*60)
        fetchReq.predicate = NSPredicate(format: "timestamp < %@", cutoff as NSDate)
        let fetchReqCont = NSFetchedResultsController(
            fetchRequest: fetchReq,
            managedObjectContext: container.viewContext,
            sectionNameKeyPath: nil, cacheName: nil)
        do {
            try fetchReqCont.performFetch()
            for object in fetchReqCont.fetchedObjects ?? [] {
                container.viewContext.delete(object)
            }
            try container.viewContext.save()
        } catch {
            print("Cannot cleanup old items \(error)")
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
        var items: [ChargeTime] = (calendarItems ?? []).map{ .calendar($0) } + manualItems.map{ .manual($0) }
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
        guard let chargeControlRanges = self.chargeControlRanges else { return nil }
        return chargeControlRanges
            .map{ [ChargeControlPoint(date: $0.start, chargeLimit: userConfig.travelChargeLevel, charging: true), ChargeControlPoint(date: $0.end, chargeLimit: userConfig.idleChargeLevel, charging: false)] }
            .joined()
            .map{ $0 }
    }
    
    func submitSchedule() async -> ScheduleStatus {
        guard let token = teslaApi.token else { return .ignoredDueToIdempotency }
        guard let pts = self.chargeControlPoints else { return .ignoredDueToInvalidChargePoints }
        guard self.calendarItems != nil else { return .ignoredDueToMissingCalendarInfo }
        do {
            let result = try await aws.schedulePushNotification(controlPoints: pts, teslafiToken: token)
            self.saveData()
            switch result {
            case .ignoredDueToIdempotency:
                return .ignoredDueToIdempotency
            case .ignoredDueToMissingAPNSEndpoint:
                return .ignoredDueToMissingAPNSEndpoint
            case .scheduled:
                return .scheduled
            }
        } catch {
            return .requestFailed(error.localizedDescription)
        }
    }
    
    let keychain: KeychainSwift = {
        let k = KeychainSwift(keyPrefix: "AppState_")
        k.synchronizable = true
        return k
    }()
    
    let container: NSPersistentContainer
    var calendarManager: CalendarManager
    var calendarUpdateTask: Task.Handle<(), Never>?
    @Published var enabledCalendars: [String]
    
    let teslaApi: TeslaSession
    var teslaApiSubscription: AnyCancellable?

    @Published var items: [ChargeTime] = []
    var calendarItems: [EKEvent]?
    var manualItems: [Item] = []
    
    var chargeScheduleSubscription: AnyCancellable?
    var aws: AWSAPI
    @Published var awsSubscribeStatus: ScheduleStatus?
    var awsSubscribeStatusSubscription: AnyCancellable?

    var fetchReqCont: NSFetchedResultsController<Item>
    
    /// Helper stuff
    @Published var userConfig: UserConfig
    var subscriptions: [AnyCancellable] = []
    var userConfigSubscription: AnyCancellable?
}

// MARK: SubmissionStatus

enum JobSubmissionStatus {
    case notTried
    case submitted
    case failed
}

// MARK: ChargeControlPoint

struct ChargeControlPoint: Hashable {
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

// MARK: ScheduleStatus
enum ScheduleStatus: Codable {
    case ignoredDueToIdempotency
    case ignoredDueToMissingCalendarInfo
    case ignoredDueToMissingTeslaFiToken
    case ignoredDueToMissingAPNSEndpoint
    case ignoredDueToInvalidChargePoints
    case requestFailed(String)
    case scheduled
    case waiting
}

