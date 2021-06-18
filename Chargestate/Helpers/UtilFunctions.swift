//
//  UtilFunctions.swift
//  Chargestate
//
//  Created by Avinash Vakil on 6/16/21.
//

import Foundation

func unimplemented<T>(message: String = "", file: StaticString = #file, line: UInt = #line) -> T {
    fatalError("unimplemented: \(message)", file: file, line: line)
}
