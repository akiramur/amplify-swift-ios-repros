import Amplify
import Foundation

final class AuthDiagnostics {
    static let shared = AuthDiagnostics()

    private let lock = NSLock()
    private let maxFileSizeBytes = 1_000_000
    private let fileName = "auth-diagnostics.log"

    private init() {}

    func configureAmplifyVerboseLogging() {
        Amplify.Logging.logLevel = .verbose
        record("config", "Amplify verbose logging enabled")
    }

    func record(_ category: String, _ message: String) {
        let line = "[\(Self.timestampFormatter.string(from: Date()))] [\(category)] \(message)\n"

        lock.lock()
        defer { lock.unlock() }

        do {
            let url = try logFileURL()
            try rotateIfNeeded(at: url)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            print("AuthDiagnostics write failed: \(error)")
        }
    }

    func shareURL() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        guard let url = try? logFileURL() else {
            return nil
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        do {
            let url = try logFileURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            FileManager.default.createFile(atPath: url.path, contents: nil)
        } catch {
            print("AuthDiagnostics clear failed: \(error)")
        }
    }

    private func rotateIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentSize = attributes[.size] as? NSNumber
        guard let currentSize, currentSize.intValue >= maxFileSizeBytes else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    private func logFileURL() throws -> URL {
        let cachesDirectory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let logsDirectory = cachesDirectory.appendingPathComponent("ReproLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        return logsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

final class AuthDiagnosticsLoggingPlugin: LoggingCategoryPlugin {
    static let pluginKey = "AuthDiagnosticsLoggingPlugin"

    private let wrappedPlugin: LoggingCategoryPlugin
    private var wrappedDefaultLogger: Logger?

    init(wrappedPlugin: LoggingCategoryPlugin = AWSUnifiedLoggingPlugin()) {
        self.wrappedPlugin = wrappedPlugin
    }

    var key: PluginKey {
        Self.pluginKey
    }

    var categoryType: CategoryType {
        .logging
    }

    var `default`: Logger {
        if let wrappedDefaultLogger {
            return wrappedDefaultLogger
        }

        let logger = AuthDiagnosticsFileLogger(
            category: "Amplify",
            wrappedLogger: wrappedPlugin.default
        )
        wrappedDefaultLogger = logger
        return logger
    }

    func configure(using configuration: Any?) throws {
        try wrappedPlugin.configure(using: configuration)
    }

    func reset() async {
        wrappedDefaultLogger = nil
        await wrappedPlugin.reset()
    }

    func logger(forCategory category: String, logLevel: LogLevel) -> Logger {
        AuthDiagnosticsFileLogger(
            category: category,
            wrappedLogger: wrappedPlugin.logger(forCategory: category, logLevel: logLevel)
        )
    }

    func logger(forCategory category: String) -> Logger {
        AuthDiagnosticsFileLogger(
            category: category,
            wrappedLogger: wrappedPlugin.logger(forCategory: category)
        )
    }

    func enable() {
        wrappedPlugin.enable()
    }

    func disable() {
        wrappedPlugin.disable()
    }

    func logger(forNamespace namespace: String) -> Logger {
        AuthDiagnosticsFileLogger(
            category: namespace,
            wrappedLogger: wrappedPlugin.logger(forNamespace: namespace)
        )
    }

    func logger(forCategory category: String, forNamespace namespace: String) -> Logger {
        AuthDiagnosticsFileLogger(
            category: "\(category).\(namespace)",
            wrappedLogger: wrappedPlugin.logger(forCategory: category, forNamespace: namespace)
        )
    }
}

private final class AuthDiagnosticsFileLogger: Logger {
    private let category: String
    private var wrappedLogger: Logger

    init(category: String, wrappedLogger: Logger) {
        self.category = category
        self.wrappedLogger = wrappedLogger
    }

    var logLevel: LogLevel {
        get { wrappedLogger.logLevel }
        set { wrappedLogger.logLevel = newValue }
    }

    func error(_ message: @autoclosure () -> String) {
        let resolved = message()
        guard shouldWrite(.error) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", resolved)
        wrappedLogger.error(resolved)
    }

    func error(error: Error) {
        guard shouldWrite(.error) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", error.localizedDescription)
        wrappedLogger.error(error: error)
    }

    func warn(_ message: @autoclosure () -> String) {
        let resolved = message()
        guard shouldWrite(.warn) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", resolved)
        wrappedLogger.warn(resolved)
    }

    func info(_ message: @autoclosure () -> String) {
        let resolved = message()
        guard shouldWrite(.info) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", resolved)
        wrappedLogger.info(resolved)
    }

    func debug(_ message: @autoclosure () -> String) {
        let resolved = message()
        guard shouldWrite(.debug) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", resolved)
        wrappedLogger.debug(resolved)
    }

    func verbose(_ message: @autoclosure () -> String) {
        let resolved = message()
        guard shouldWrite(.verbose) else { return }
        AuthDiagnostics.shared.record("amplify.\(category)", resolved)
        wrappedLogger.verbose(resolved)
    }

    private func shouldWrite(_ level: LogLevel) -> Bool {
        logLevel.rawValue >= level.rawValue
    }
}
