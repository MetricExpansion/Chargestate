//
//  ChargestateApp.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import SwiftUI

@main
struct ChargestateApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
