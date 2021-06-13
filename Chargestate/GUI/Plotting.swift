//
//  Plotting.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/12/21.
//

import Foundation
import SwiftUICharts
import SwiftUI

@MainActor
func timepointsChartData(_ appState: AppState) -> [Double] {
    let chargeRanges = appState.chargeControlRanges
    let points = (0...24).map{ hour -> Double in
        let date = Date().addingTimeInterval(Double(hour * 60 * 60))
        let isCharging = chargeRanges.contains{ range in range.contains(date)}
        return (isCharging ? appState.travelChargeLevel : appState.idleChargeLevel) * 100
    }
    return points
}
