import Foundation
import Shared

/// Говорит с `codex app-server` по JSON-RPC через stdin/stdout (по одному
/// JSON-объекту на строку, без Content-Length-обрамления). Процесс живёт
/// только на время одного опроса — держать его постоянно живым можно будет
/// оптимизировать позже.
enum CodexAppServerError: Error, LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case timedOut
    case rpcError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Не найден бинарник codex CLI (проверь `codex login`)."
        case .launchFailed(let m):
            return "Не удалось запустить codex app-server: \(m)"
        case .timedOut:
            return "codex app-server не ответил вовремя."
        case .rpcError(let m):
            return "codex app-server вернул ошибку: \(m)"
        case .parseFailed(let m):
            return "Не удалось разобрать ответ codex app-server: \(m)"
        }
    }
}

enum CodexAppServer {
    /// Известные места, где может лежать codex CLI, если его нет в PATH
    /// (например, он идёт в комплекте с приложением ChatGPT.app).
    private static let candidatePaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        NSHomeDirectory() + "/.codex/plugins/.plugin-appserver/codex"
    ]

    private static func resolveBinaryPath() -> String? {
        let fm = FileManager.default
        if let fromPath = which("codex"), fm.isExecutableFile(atPath: fromPath) {
            return fromPath
        }
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    static func fetch() async throws -> ProviderUsage {
        guard let binaryPath = resolveBinaryPath() else {
            throw CodexAppServerError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["app-server"]

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }
        defer {
            if process.isRunning { process.terminate() }
        }

        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            stdin.fileHandleForWriting.write(data)
            stdin.fileHandleForWriting.write("\n".data(using: .utf8)!)
        }

        try send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["clientInfo": ["name": "reset-widget-host", "title": "Reset Widget", "version": "0.1.0"]]
        ])

        let result = try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                try await readRateLimitsResponse(stdout: stdout, stdin: stdin, send: send)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw CodexAppServerError.timedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            throw CodexAppServerError.parseFailed("нет поля rateLimits")
        }
        return ProviderUsage(
            session: usageWindow(rateLimits["primary"]),
            weekly: usageWindow(rateLimits["secondary"]),
            planLabel: rateLimits["planType"] as? String,
            errorMessage: nil
        )
    }

    private static func readRateLimitsResponse(
        stdout: Pipe,
        stdin: Pipe,
        send: @escaping ([String: Any]) throws -> Void
    ) async throws -> [String: Any] {
        var buffer = Data()
        var sentRateLimitsRequest = false

        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                guard !lineData.isEmpty,
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                if obj["id"] as? Int == 1, !sentRateLimitsRequest {
                    sentRateLimitsRequest = true
                    try send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": [:]])
                    continue
                }
                if obj["id"] as? Int == 2 {
                    if let error = obj["error"] as? [String: Any] {
                        throw CodexAppServerError.rpcError("\(error["message"] ?? error)")
                    }
                    guard let result = obj["result"] as? [String: Any] else {
                        throw CodexAppServerError.parseFailed("ответ id=2 без result")
                    }
                    return result
                }
            }
        }
    }

    private static func usageWindow(_ any: Any?) -> UsageWindow? {
        guard let dict = any as? [String: Any] else { return nil }
        let percent: Double
        if let d = dict["usedPercent"] as? Double {
            percent = d
        } else if let i = dict["usedPercent"] as? Int {
            percent = Double(i)
        } else {
            percent = 0
        }
        let resets = (dict["resetsAt"] as? Int).map { Date(timeIntervalSince1970: Double($0)) }
        return UsageWindow(usedPercent: percent, resetsAt: resets)
    }
}
