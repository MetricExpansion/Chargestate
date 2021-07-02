//
//  ContentView.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import SwiftUI
import CoreData
import EventKit
import SwiftUICharts

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State var showingAddSheet: Bool = false
    @State var showingSettingsSheet: Bool = false
    
    var body: some View {
        VStack {
            List {
                Label("Charge Projection", systemImage: "bolt.fill.batteryblock.fill")
                    .listRowSeparator(.hidden)
                LineView(data: timepointsChartData(appState), style: chartStyle())
                    .frame(height: 300)
                SubmissionStatusIndicator(submissionStatus: $appState.awsSubscribeStatus)
                ForEach(appState.itemsGroupedByDate) { section in
                    Section("\(section.date.formatted(.dateTime.day().month(.wide).year()))") {
                        ForEach(section.chargeTimes) { item in
                            switch item {
                            case .manual(let item):
                                ManualItemView(item: item)
                            case .calendar(let item):
                                CalendarItemView(event: item)
                                    .deleteDisabled(true)
                            }
                        }
                        .onDelete { indexSet in
                            let itemsToDelete = indexSet
                                .map { section.chargeTimes[$0] }
                                .compactMap{ $0.manualItem() }
                            deleteItems(items: itemsToDelete)
                        }
                    }
                }
            }
            .animation(appState.items.isEmpty ? .none : .default, value: appState.items)
            .navigationBarItems(leading: HStack {
                EditButton()
                    .padding(.trailing)
                Button(action: {
                    showingSettingsSheet = true
                }) {
                    Image(systemName: "gear")
                }
            }, trailing: Button(action: {
                showingAddSheet = true
            }) {
                Image(systemName: "plus")
                Text("Add")
            }
            .buttonStyle(.bordered))
        .navigationTitle("Chargestate")
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: {}) {
            NavigationView {
                ManualItemEditor(date: Date(), showing: $showingAddSheet) { date in
                    let newEntry = Item(context: appState.container.viewContext)
                    newEntry.timestamp = date
                    do {
                        try newEntry.managedObjectContext?.save()
                    } catch {
                        print("Failed to save!")
                    }
                }
            }
            .accentColor(.green)
        }
        .sheet(isPresented: $showingSettingsSheet, onDismiss: {}) {
            NavigationView {
                Settings(onFinish: { showingSettingsSheet = false })
            }
            .accentColor(.green)
        }
        .onAppear{
            async {
                await appState.aws.preparePushNotifications()
//                await appState.aws.schedulePushNotification(atDate: Date().addingTimeInterval(15))
            }
        }
    }

    private func addItem() {
        appState.add()
    }
    
    private func chartStyle() -> ChartStyle {
        let style = Styles.lineChartStyleOne
        style.backgroundColor = Color.clear
        style.darkModeStyle = Styles.lineViewDarkMode
        style.darkModeStyle!.backgroundColor = Color.clear
        return style
    }
    
    private func deleteItems(items: [Item]) {
        items.forEach(appState.container.viewContext.delete)
        do {
            try appState.container.viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

struct ManualItemView: View {
    @State var showingEditor = false
    @ObservedObject var item: Item
    var body: some View {
        Button {
            showingEditor = true
        } label: {
            HStack {
                Image(systemName: "clock")
                Text("Ready By...")
                Spacer()
                Text(item.timestamp ?? Date(), formatter: itemFormatter)
                    .padding(.trailing)
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
        }) {
            NavigationView {
                ManualItemEditor(date: item.timestamp!, showing: $showingEditor) { date in
                    item.timestamp = date
                    do {
                        try item.managedObjectContext?.save()
                    } catch {
                        print("Failed to save!")
                    }
                }
            }
        }
    }
}

struct CalendarItemView: View {
    let event: EKEvent
    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(Color(event.calendar.cgColor))
            VStack {
                HStack {
                    Text("CALENDAR EVENT")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
                HStack {
                    Text("\(event.title)")
                    Spacer()
                }
            }
            Text(event.startDate, formatter: itemFormatter)
                .padding(.trailing)
        }
    }
}

struct SubmissionStatusIndicator: View {
    @Binding var submissionStatus: ScheduleStatus?
    @StateObject var animationStatus = StateManager()

    var body: some View {
        HStack {
            Image(systemName: "cloud")
                .foregroundColor(.accentColor)
            Text(labelData.0)
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: labelData.1)
                .padding(.trailing)
                .foregroundColor(labelData.2)
        }
        .listRowBackground(AnimatedEllipses(
            loadingColor: .blue,
            finishedColor: (submissionStatus?.isFailure ?? false) ? .red : .green,
            loading: animationStatus)
                            .background(.background)
                            .onChange(of: submissionStatus) { status in
            if status?.isFinished ?? true {
                animationStatus.setCompleted()
            } else {
                animationStatus.setStarted()
            }
        })
    }
    
    var labelData: (String, String, Color) {
        switch submissionStatus {
        case .none:
            return ("No Status", "questionmark.circle.fill", .gray)
        case .ignoredDueToIdempotency:
            return ("Server Up to Date", "checkmark.circle.fill", .green)
        case .ignoredDueToMissingCalendarInfo:
            return ("ERROR: Failed to Get Calendar Info", "exclamationmark.circle.fill", .red)
        case .ignoredDueToMissingTeslaFiToken:
            return ("ERROR: No TeslaFi Token Entered", "exclamationmark.circle.fill", .yellow)
        case .ignoredDueToMissingAPNSEndpoint:
            return ("ERROR: Push Notification Not Enabled", "exclamationmark.circle.fill", .yellow)
        case .ignoredDueToInvalidChargePoints:
            return ("ERROR: Invalid Charge Settings", "exclamationmark.circle.fill", .yellow)
        case .requestFailed(_):
            return ("ERROR: Failed to Submit Schedule", "xmark.circle.fill", .red)
        case .scheduled:
            return ("Server Up to Date", "checkmark.circle.fill", .green)
        case .waiting:
            return ("Waiting...", "ellipsis.rectangle.fill", .gray)
        }
    }
}
    
struct ContentView_Previews: PreviewProvider {
    static var appState = AppState.preview
    static var previews: some View {
        NavigationView {
            ContentView()
        }
        .environmentObject(appState)
//        .environment(\.colorScheme, .dark)
    }
}
