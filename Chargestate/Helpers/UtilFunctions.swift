//
//  UtilFunctions.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import Foundation
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
