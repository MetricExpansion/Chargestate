//
//  Settings.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import SwiftUI

struct Settings: View {
    @EnvironmentObject var appState: AppState
    @State var userConfigLocal: UserConfig = UserConfig.defaultValues
    let onFinish: () -> ()
    var body: some View {
        Form {
            Section("TeslaFi Account") {
                LoginStatus(teslaApi: appState.teslaApi)
            }
            Section("Charging") {
                ChargeSettingEditor(value: $userConfigLocal.travelChargeLevel, range: 50...100, scale: 1.0) {
                    HStack {
                        Image(systemName: "battery.100")
                            .foregroundColor(.green)
                        Text("Travel Charge Level")
                    }
                }
                .listRowBackground(ProgressBarBackground(frac: userConfigLocal.travelChargeLevel, color: .green))
                
                ChargeSettingEditor(value: $userConfigLocal.idleChargeLevel, range: 50...100, scale: 1.0) {
                    HStack {
                        Image(systemName: "battery.75")
                            .foregroundColor(.yellow)
                        Text("Idle Charge Level")
                    }
                }
                .listRowBackground(ProgressBarBackground(frac: userConfigLocal.idleChargeLevel, color: .yellow))
                
                ChargeSettingEditor(value: $userConfigLocal.chargeRate, range: 0...100, scale: 0.10) {
                    HStack {
                        Image(systemName: "battery.100.bolt")
                            .foregroundColor(.indigo)
                        Text("Charge Rate (%/hr)")
                    }
                }
                .listRowBackground(ProgressBarBackground(frac: userConfigLocal.chargeRate, scale: 0.10, color: .indigo))

            }
            Section("Debug") {
                ChargeStatus(teslaApi: appState.teslaApi)
                SetCharge(teslaApi: appState.teslaApi)
                Button(action: { appState.resetBgStats() }) {
                    HStack(alignment: .top) {
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(appState.backgroundCountDebug) Background Updates")
                            if let date = appState.backgroundLastPerformed {
                                Text("Last BG Update: \(date.formatted(.dateTime.year().month().day().hour().minute()))")
                            } else {
                                Text("Last BG Update: N/A")
                            }
                        }
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .toolbar(content: {
            ToolbarItemGroup(placement: .keyboard, content: {
                Spacer()
                Button(action: { hideKeyboard() }) { Text("Done") }
            })
        })
        .onAppear {
            print(appState.userConfig)
            userConfigLocal = appState.userConfig
        }
        .navigationTitle("Settings")
        .navigationBarItems(trailing: Button(action: {
            appState.userConfig = userConfigLocal
            onFinish()
        }) { Text("Done").bold() })
    }
}

struct ProgressBarBackground: View {
    init(frac: Double, scale: Double = 1.0, color: Color = .primary) {
        self.frac = frac / scale
        self.color = color
    }
    
    let frac: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(Color(UIColor.systemBackground))
                Rectangle()
                    .frame(width: (frac).clamped(to: 0.0...1.0) * geo.size.width, height: geo.size.height)
                    .foregroundColor(color)
                    .opacity(0.2)
                    .animation(.linear(duration: 0.15), value: frac)
            }
        }
    }
}

struct ChargeStatus: View {
    @ObservedObject var teslaApi: TeslaSession
    var body: some View {
        HStack {
            Text("Current Target SOC")
            Spacer()
            Text(teslaApi.currentSelectedSoc?.formatted(.percent) ?? "N/A")
            Button(action: { async { try? await teslaApi.getVehicleState() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(teslaApi.requestInFlight)
        }
    }
}

struct SetCharge: View {
    @ObservedObject var teslaApi: TeslaSession
    @AppStorage("SettingsMenu_chargeSetting") var chargeSetting: Double = 0.90
    @State var error: Bool = false
    @State var errorDetailed: String = ""
    var body: some View {
        Group {
            ChargeSettingEditor(value: $chargeSetting, range: 50...100, scale: 1.0) {
                Text("Set Target SOC")
            }
            .listRowBackground(ProgressBarBackground(frac: chargeSetting, color: .blue))
            Button(action: {
                async {
                    do {
                        try await teslaApi.setChargeLimit(percent: Int(100 * chargeSetting))
                    } catch {
                        self.error = true
                        self.errorDetailed = error.localizedDescription
                    }
                }
            }) {
                HStack {
                    Spacer()
                    Text("Set")
                    Image(systemName: "paperplane.circle.fill")
                }
            }
            .disabled(teslaApi.requestInFlight)
            .alert(Text("\(errorDetailed)"), isPresented: $error, presenting: errorDetailed) { v in
                Text("Failed because \(v)")
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
                        .onDisappear {
                            if token != "" {
                                teslaApi.token = token
                            } else {
                                teslaApi.token = nil
                            }
                        }
                }
            }
        }
        .navigationTitle("Login to TeslaFi")
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
        Settings(onFinish: {})
            .environmentObject(appState)
    }
}

struct ChargeSettingEditor<V: View>: View {
    @Binding var value: Double
    let range: ClosedRange<Int>
    let scale: Double
    let label: () -> V
    
    @State var text: String = ""
    @State private var originalValue: Double? = nil

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gestureData in
                if originalValue == nil {
                    originalValue = value
                }
                value = Double(Int((originalValue! + scale * 0.002 * gestureData.translation.width) * 100.0).clamped(to: range)) / 100.0
            }
            .onEnded { _ in
                originalValue = nil
            }
    }
    
    var body: some View {
        HStack {
            label()
            Spacer()
            TextField("Value", text: $text, onEditingChanged: {
                if $0 == true { return }
                guard let v = Int(text) else { return }
                value = Double(v.clamped(to: range)) / 100.0
                text = Int(value * 100).formatted()
            })
            .onChange(of: value) { newValue in
                let newText = Int(newValue * 100).formatted()
                if newText != text { text = newText }
            }
//            .onChange(of: text) { v in
//                print("onChange of text: \(text)")
//                guard let v = Int(text) else { return }
//                value = Double(v) / 100.0
//                print("onChange of text: new value is \(value)")
//            }
            .onAppear {
                text = Int(value * 100).formatted()
            }
            .frame(maxWidth: 50)
            .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            Text("%")
        }
        .gesture(dragGesture)
    }
}

