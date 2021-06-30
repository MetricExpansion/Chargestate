//
//  AWSAPI.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/25/21.
//

import Foundation
import AWSSNS
import AWSLambda
import UserNotifications
import Combine
import CommonCrypto

class AWSAPI: NSObject, Codable {
    override init() {
        super.init()
    }

    init(endpoint: String?) {
        self.endpoint = endpoint
        super.init()
    }
    
    var endpoint: String?
    private var token: String?
    
    var lastInvokationArn: String?
    var lastInvocationHash: String?

    
    func saveTo(userDefaults: UserDefaults, key: String) {
        let encoder = JSONEncoder()
        guard let selfEncoded = try? encoder.encode(self) else {
            return
        }
        userDefaults.set(selfEncoded, forKey: key)
        print("AWS saved")
    }
    
    func preparePushNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            print("Permission granted: \(granted)")
            await getNotificationSettings()
        } catch {
            print("Could not get notification permission setting.")
        }
        UNUserNotificationCenter.current()
    }

    func getNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        print("Notification settings: \(settings)")
        guard settings.authorizationStatus == .authorized else { return }
        await UIApplication.shared.registerForRemoteNotifications()
        // Function will continue in `acceptToken`...
    }
    
    fileprivate func createEndpoint(_ token: String, _ platformArn: String, _ sns: AWSSNS) async {
        //   call create platform endpoint
        let createEndpointIn = AWSSNSCreatePlatformEndpointInput()!
        createEndpointIn.token = token
        createEndpointIn.platformApplicationArn = platformArn
        do {
            let response = try await sns.createPlatformEndpoint(createEndpointIn)
            //   store the returned platform endpoint ARN
            self.endpoint = response.endpointArn
        } catch {
            print("Could not create endpoint: \(error)")
            return
        }
    }
    
    func acceptToken(token: String) async {
        let platformArn = "arn:aws:sns:us-west-2:017451542414:app/APNS_SANDBOX/ChargestateApp"
        // retrieve the latest device token from the mobile operating system
        self.token = token
        let sns = AWSSNS.default()
        // if (the platform endpoint ARN is not stored)
        //   # this is a first-time registration
        if endpoint == nil {
            await createEndpoint(token, platformArn, sns)
        }

        guard let endpoint = self.endpoint else {
            return
        }
        
        // call get endpoint attributes on the platform endpoint ARN
        let reqAttrs = AWSSNSGetEndpointAttributesInput()!
        reqAttrs.endpointArn = endpoint
        do {
            let attrs = try await sns.getEndpointAttributes(reqAttrs)
            // if (the device token in the endpoint does not match the latest one) or
            // (get endpoint attributes shows the endpoint as disabled)
            if attrs.attributes!["Token"] != token || attrs.attributes!["Enabled"] == "false" {
                // call set endpoint attributes to set the latest device token and then enable the platform endpoint
                // TODO: Should not delete and recreate, but instead just modify. Couldn't get it to work the first time.
                let delReq = AWSSNSDeleteEndpointInput()!
                delReq.endpointArn = endpoint
                do {
                    let _ = try await sns.deleteEndpoint(delReq)
                    await createEndpoint(token, platformArn, sns)
                } catch {
                    print("Could not update endpoint attributes: \(error)")
                }
            }
        } catch {
            // if (while getting the attributes a not-found exception is thrown)
            // # the platform endpoint was deleted
            if (error as NSError).code == AWSSNSErrorType.notFound.rawValue {
                // call create platform endpoint with the latest device token
                // store the returned platform endpoint ARN
                await createEndpoint(token, platformArn, sns)
            }
        }
    }
    
    func schedulePushNotification(controlPoints cpIn: [ChargeControlPoint], teslafiToken: String) async throws -> ScheduleStatus {
        guard let endpoint = self.endpoint else { return .ignored }
        // Hash this input to avoid sending duplicate requests.
        let controlPoints = cpIn.filter{ $0.date > Date() }
        let hash = (controlPoints.description + teslafiToken.description).sha1()
        if lastInvocationHash == hash { return .ignored }
        
        // Set the state in case this function is called again while suspended.
        let oldLastInvocationHash = lastInvocationHash
        lastInvocationHash = hash
        let oldLastInvocationArn = lastInvokationArn
        lastInvokationArn = nil
        
        let lambda = AWSLambda.default()
        
        let req = AWSLambdaInvocationRequest()
        req?.functionName = "arn:aws:lambda:us-west-2:017451542414:function:ChargestateTriggerLambda"
        let data = ScheduleRequest(
            Name: UUID().uuidString,
            AlsoCancel: oldLastInvocationArn,
            Input: .init(
                TriggerTime: Date(),
                TargetEndpoint: endpoint,
                Message: "{\"aps\":{\"content-available\":1}}",
                Events: controlPoints.map{ pt in .init(TriggerTime: pt.date, Token: teslafiToken, Percent: Int(100 * pt.chargeLimit)) }
            )
        )
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        do {
            req?.payload = try jsonEncoder.encode(data)
            let response = try await lambda.invoke(req!)
            print(response)
            guard
                let l1 = response.payload as? NSDictionary,
                let l2 = l1.object(forKey: "body") as? NSDictionary,
                let executionArn = l2.value(forKey: "executionArn"),
                let executionArn = executionArn as? String
            else { throw AWSAPIInternalErrors.requestFailed }
            print("Scheduled push notification with execution ARN \(executionArn)")
            lastInvokationArn = executionArn
            return .scheduled
        } catch {
            lastInvocationHash = oldLastInvocationHash
            lastInvokationArn = oldLastInvocationArn
            throw AWSAPIError.schedulingFailed(error)
        }
    }
}

enum ScheduleStatus {
    case ignored
    case scheduled
}

enum AWSAPIError: Error {
    case schedulingFailed(Error)
}

enum AWSAPIInternalErrors: Error {
    case requestFailed
}

struct SFNEvent: Codable {
    let TriggerTime: Date
    let Token: String
    let Percent: Int
}


struct SFNInput: Codable {
    let TriggerTime: Date
    let TargetEndpoint: String
    let Message: String
    let Events: [SFNEvent]
}

struct ScheduleRequest: Codable {
    let Name: String
    let AlsoCancel: String?
    let Input: SFNInput
}


extension AWSSNS {
    func getEndpointAttributes(
        _ request: AWSSNSGetEndpointAttributesInput
    ) async throws -> AWSSNSGetEndpointAttributesResponse {
        try await withCheckedThrowingContinuation { continuation in
            getEndpointAttributes(request) { result, error  in
                if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: error!)
                }
            }
        }
    }
}

extension String {
    func sha1() -> String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
