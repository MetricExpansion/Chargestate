//
//  ChargestateApp.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import SwiftUI

@main
struct ChargestateApp: App {
    @StateObject var appState = AppState(loadCalendar: true)
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
                    .accentColor(.green)
            }
            .environmentObject(appState)
        }
    }
}
