import Foundation

class Logger {
    static let shared = Logger()
    let logFilePath: String

    private init() {
        logFilePath = "/tmp/handsoff.log"
        FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
    }

    func log(_ message: String) {
        if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
            if let data = ("\(Date()): \(message)\n").data(using: .utf8) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            print("Failed to open log file")
        }
    }
}
