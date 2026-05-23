import Foundation

// MARK: - CLI Argument Parsers

func parseTarget(from args: [String]) -> String {
    guard let idx = args.firstIndex(of: "--target"), idx + 1 < args.count else {
        return "豆包输入法"
    }
    return args[idx + 1]
}

func parseDelay(from args: [String]) -> UInt32 {
    guard let idx = args.firstIndex(of: "--delay"), idx + 1 < args.count,
          let ms = UInt32(args[idx + 1]) else { return 3000 }
    return ms
}
