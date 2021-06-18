//
//  Settings.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import SwiftUI

struct Settings: View {
    @EnvironmentObject var appState: AppState
    let onFinish: () -> ()
    var body: some View {
        Form {
            Section("TeslaFi Account") {
                LoginStatus(teslaApi: appState.teslaApi)
                ChargeStatus(teslaApi: appState.teslaApi)
            }
            Section("Charging") {
                ChargeSettingEditor(label: "Travel Charge Level", systemImage: "battery.100", keyPath: \.travelChargeLevel)
                ChargeSettingEditor(label: "Idle Charge Level", systemImage: "battery.75", keyPath: \.idleChargeLevel)
                ChargeSettingEditor(label: "Charge Rate (%/hr)", systemImage: "battery.100.bolt", keyPath: \.chargeRate)
            }

        }
        .navigationTitle("Settings")
        .navigationBarItems(trailing: Button(action: onFinish) { Text("Done").bold() })
    }
}

struct ChargeStatus: View {
    @ObservedObject var teslaApi: TeslaSession
    var body: some View {
        HStack {
            Label("Current Target SOC", systemImage: "bolt.fill.batteryblock.fill")
            Spacer()
            Text(teslaApi.currentSelectedSoc?.formatted(.percent) ?? "N/A")
            Button(action: { async { try? await teslaApi.getVehicleState() } }) {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
}


struct LoginStatus: View {
    enum NavSelection: Hashable {
        case login
    }
    @ObservedObject var teslaApi: TeslaSession
    @State var navSelection: NavSelection?
    
    var body: some View {
        NavigationLink(
            tag: .login,
            selection: $navSelection,
            destination: {
                LoginField(teslaApi: teslaApi)
            }) {
            HStack {
                Label("API Token", systemImage: "key.fill")
                Spacer()
                Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "xmark.diamond.fill")
                    .foregroundColor(isLoggedIn ? .green : .red)
            }
        }
    }
    
    var isLoggedIn: Bool {
        teslaApi.token != nil
    }
}

struct LoginField: View {
    @ObservedObject var teslaApi: TeslaSession
    @State var token: String = ""

    var body: some View {
        ZStack {
            Form {
                Section("TeslaFi Account Details") {
                    TextField("TeslaFi API Token", text: $token)
                        .onAppear {
                            token = teslaApi.token ?? ""
                        }
                        .onChange(of: token) { token in
                            if token != "" {
                                teslaApi.token = token
                            } else {
                                teslaApi.token = nil
                            }
                        }
                }
            }
        }
        .navigationTitle("Login to Tesla")
    }
}

struct LoginFields: View {
    @ObservedObject var teslaApi: TeslaSession
    var body: some View {
        HStack {
            Label("Login Status", systemImage: "person.circle")
            Spacer()
            Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "xmark.diamond.fill")
                .foregroundColor(isLoggedIn ? .green : .red)
                .padding(.trailing)
        }
    }
    
    var isLoggedIn: Bool {
        teslaApi.token != nil
    }
}


struct Settings_Previews: PreviewProvider {
    static var appState = AppState.preview
    static var previews: some View {
        NavigationView {
            Settings(onFinish: {})
                .environmentObject(appState)
        }
    }
}

struct ChargeSettingEditor: View {
    @EnvironmentObject var appState: AppState
    let label: LocalizedStringKey
    let systemImage: String
    let keyPath: WritableKeyPath<UserConfig, Double>
    @State var text: String = ""
    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            TextField("Value", text: $text, onEditingChanged: { started in
                guard !started else { return }
                guard let v = Int(text) else { return }
                appState.userConfig[keyPath: keyPath] = Double(v) / 100.0
            })
                .onAppear{ text = Int(appState.userConfig[keyPath: keyPath] * 100).formatted() }
                .frame(maxWidth: 50)
                .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            Text("%")
        }
    }
}

