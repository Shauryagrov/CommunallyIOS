//
//  Log.swift
//  Communally
//
//  Tiny debug-only logger. `Log.debug(...)` compiles to a no-op in
//  Release builds, so messages that include PII (user names, emails,
//  payment amounts, GPS) won't be visible via Console.app on a Mac
//  with the device connected once we ship.
//
//  Pattern: replace bare `print("...")` with `Log.debug("...")`.
//  The @autoclosure means the interpolated string isn't even
//  evaluated in Release, so `Log.debug("Saved user: \(user.fullName)")`
//  pays zero runtime cost.
//

import Foundation

enum Log {
    /// Prints in DEBUG, compiles away in Release. Use for anything that
    /// would be embarrassing to find in a customer's Console.app feed.
    static func debug(_ message: @autoclosure () -> String,
                      file: String = #fileID,
                      line: Int = #line) {
        #if DEBUG
        print("[\(file):\(line)] \(message())")
        #endif
    }
}
