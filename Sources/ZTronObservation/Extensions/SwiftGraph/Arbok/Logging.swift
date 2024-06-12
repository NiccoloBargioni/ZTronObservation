import Foundation

internal struct Log: TextOutputStream {

    internal func write(_ string: String) {
        let fm = FileManager.default
        let log = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("log.txt")
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(string.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? string.data(using: .utf8)?.write(to: log)
        }
    }
    
    internal func clearLogFile() {
        let fileName = "Log"
        let dir = try? FileManager.default.url(for: .documentDirectory,
              in: .userDomainMask, appropriateFor: nil, create: true)

        guard let fileURL = dir?.appendingPathComponent(fileName).appendingPathExtension("txt") else {
            fatalError("Not able to create URL")
        }

        let text = ""
        try! text.write(to: fileURL, atomically: false, encoding: .utf8)
    }
}

var logging = Log()

