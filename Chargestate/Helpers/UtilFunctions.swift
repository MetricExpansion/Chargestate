//
//  UtilFunctions.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import Foundation
import Combine
import SwiftUI

func unimplemented<T>(message: String = "", file: StaticString = #file, line: UInt = #line) -> T {
    fatalError("unimplemented: \(message)", file: file, line: line)
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Color {
    static func listBgForScheme(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color.white
        case .dark:
            return Color(red: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0)
        @unknown default:
            return Color.white
        }
    }
}
