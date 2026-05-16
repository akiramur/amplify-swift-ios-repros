import Foundation
import OSLog

enum LogCapture {
    private static let fileManager = FileManager.default
    private static var captureStartDate = Date()
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func startVerboseCapture() -> URL? {
        let url = processOutputLogURL
        captureStartDate = Date()
        do {
            try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            fileManager.createFile(atPath: url.path, contents: nil)
        } catch {
            return nil
        }

        fflush(stdout)
        fflush(stderr)
        freopen(url.path, "a+", stdout)
        freopen(url.path, "a+", stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        print("[LogCapture] started \(timestampFormatter.string(from: Date()))")
        return url
    }

    static func snapshotUnifiedLog() -> URL? {
        guard #available(iOS 15.0, *) else { return nil }

        let destinationURL = temporaryExportURL(prefix: "unified-log", fileExtension: "log")
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: captureStartDate.addingTimeInterval(-2))
            let entries = try store.getEntries(with: [], at: position, matching: nil)

            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                let level = String(describing: entry.level)
                let subsystem = entry.subsystem
                let category = entry.category
                let message = entry.composedMessage
                let timestamp = timestampFormatter.string(from: entry.date)
                lines.append("[\(timestamp)] [\(subsystem)] [\(category)] [\(level)] \(message)")
            }

            let body = lines.joined(separator: "\n")
            try body.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        } catch {
            return nil
        }
    }

    static func snapshotVerboseLog() -> URL? {
        guard let sourceURL = preferredVerboseLogURL else { return nil }
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }

        let destinationURL = temporaryExportURL(prefix: "amplify-verbose", fileExtension: "log")
        fflush(stdout)
        fflush(stderr)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    static func writeReproReport(contents: String) -> URL? {
        let destinationURL = temporaryExportURL(prefix: "repro-report", fileExtension: "txt")
        do {
            try contents.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        } catch {
            return nil
        }
    }

    static var preferredVerboseLogURL: URL? {
        if let authDiagnosticsURL = AuthDiagnostics.shared.shareURL(),
           fileManager.fileExists(atPath: authDiagnosticsURL.path) {
            return authDiagnosticsURL
        }
        return fileManager.fileExists(atPath: processOutputLogURL.path) ? processOutputLogURL : nil
    }

    static var verboseLogURL: URL {
        preferredVerboseLogURL ?? processOutputLogURL
    }

    static var processOutputLogURL: URL {
        logsDirectoryURL.appendingPathComponent("amplify-verbose.log")
    }

    private static var logsDirectoryURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReproLogs", isDirectory: true)
    }

    private static func temporaryExportURL(prefix: String, fileExtension: String) -> URL {
        let filename = "\(prefix)-\(timestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).\(fileExtension)"
        return fileManager.temporaryDirectory.appendingPathComponent(filename)
    }
}
