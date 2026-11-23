import Foundation

/// 仅在带 --debug 启动时写文件日志，避免影响正常运行
let debugEnabled = true

func dbg(_ message: String) {
    guard debugEnabled else { return }
    let line = "\(Date().timeIntervalSince1970) \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/launcher-debug.log")
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
