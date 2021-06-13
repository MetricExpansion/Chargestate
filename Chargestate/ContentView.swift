//
//  ContentView.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import SwiftUI
import CoreData
import EventKit

struct ContentView: View {
    @StateObject var appState: AppState
    var body: some View {
        VStack {
            List {
//                ForEach(appState.items) { item in
//                    switch item {
//                    case .manual(let item):
//                        ManualItemView(item: item)
//                    case .calendar(let item):
//                        CalendarItemView(event: item)
//                            .deleteDisabled(true)
//                    }
//                }
//                .onDelete(perform: deleteItems)
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
            .navigationBarItems(leading: EditButton(), trailing: Button(action: addItem) {
                Label("Add Item", systemImage: "plus")
            })
        .navigationTitle("Chargestate")
        }
    }

    private func addItem() {
        appState.add()
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
    formatter.timeStyle = .medium
    return formatter
}()

struct ManualItemView: View {
    let item: Item
    var body: some View {
        HStack {
            Text("Ready By")
            Spacer()
            Text(item.timestamp!, formatter: itemFormatter)
        }
    }
}

struct CalendarItemView: View {
    let event: EKEvent
    var body: some View {
        HStack {
            VStack {
                HStack {
                    Text("CALENDAR ITEM")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                HStack {
                    Text("\(event.title)")
                    Spacer()
                }
            }
            Text(event.startDate, formatter: itemFormatter)
        }
    }
}
    
struct ContentView_Previews: PreviewProvider {
    static var appState = AppState.preview
    static var previews: some View {
        NavigationView {
            ContentView(appState: appState)
        }
    }
}
