//
//  TeslaAPI.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import Foundation

class TeslaSession: ObservableObject {

    @Published var token: String?
    @Published var currentSelectedSoc: Int?
    
    init() {
    }
    
    init(token: String?) {
        self.token = token
    }
    
    func login(token: String) {
        self.token = token
    }
    
    func logout() {
        self.token = nil
    }
    
    func setChargeLimit(percent: Int) async throws {
    }
    
    func getVehicleState() async throws {
        print("Refresh requested")
        guard let req = getCommandRequest(command: "lastGood") else {
            throw NoCredentialsFailure()
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        let tfdata = try jsonDecoder.decode(TeslaFiAPIData.self, from: data)
        currentSelectedSoc = Int(tfdata.chargeLimitSoc ?? "") ?? currentSelectedSoc
    }

    
    fileprivate func getCommandRequest(command: String, wakeVehicle: Bool = false) -> URLRequest? {
        guard let token = self.token else { return nil }
        var string = "https://www.teslafi.com/feed.php?token=\(token)&command=\(command)"
        if wakeVehicle {
            string += "&wake=60"
        }
        guard let url = URL(string: string) else { return nil }
        let urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 75)
        return urlRequest
    }
    
    lazy var jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

struct TeslaFiAPIData: Codable {
    let chargeLimitSoc: String?
    let chargeCurrentRequest: String?
    let chargerVoltage: String?
    let connChargeCable: String?
}

struct NoCredentialsFailure: Error {}
struct LoginFailure: Error {}
struct DecodeFailure: Error {}
