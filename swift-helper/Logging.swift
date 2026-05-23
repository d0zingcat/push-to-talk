import Foundation
import AppKit

import Foundation
import Carbon
import CoreGraphics
import AppKit
import SwiftUI

func logDaemon(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date())
    let line = "[\(timestamp)] \(message)"
    print(line)
    fflush(stdout)
    
    // Also append to state manager if GUI is running
    DispatchQueue.main.async {
        if NSApplication.shared.delegate != nil {
            AppStateManager.shared.logs.append(line)
            if AppStateManager.shared.logs.count > 100 {
                AppStateManager.shared.logs.removeFirst()
            }
        }
    }
}
