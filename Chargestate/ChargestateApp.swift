//
//  ChargestateApp.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/11/21.
//

import Foundation
import UIKit
import SwiftUI
import AWSCore

@main
struct ChargestateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
            }
            .accentColor(.green)
            .environmentObject(appDelegate.appState)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                appDelegate.saveData()
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    // The main app state
    lazy var appState = AppState()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: .USWest2,
            identityPoolId: "us-west-2:85571169-008f-4192-9512-75d999ca6c52")
        let configuration = AWSServiceConfiguration(
            region: .USWest2,
            credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        async { await appState.aws.acceptToken(token: token) }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register: \(error)")
    }
    
    func saveData() {
        appState.saveData()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        appState.saveData()
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("Got a background notification: \(userInfo)")
        completionHandler(.noData)
    }
}
