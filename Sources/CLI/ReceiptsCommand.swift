// ReceiptsCommand.swift - `youxpc receipts`: read back what the agent did
//
//   youxpc receipts              the last 40 events
//   youxpc receipts --last 200   more of them
//   youxpc receipts --today      only today's
//   youxpc receipts --run ID     one server run
//   youxpc receipts --summary    totals per day
//   youxpc receipts --json       raw JSON lines, for scripts

import Foundation
import YouxPC

struct ReceiptsCommand {

    func run(_ arguments: [String]) {
        var limit = 40
        var todayOnly = false
        var runFilter: String?
        var summary = false
        var json = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--last":
                index += 1
                limit = index < arguments.count ? (Int(arguments[index]) ?? limit) : limit
            case "--today": todayOnly = true
            case "--run":
                index += 1
                runFilter = index < arguments.count ? arguments[index] : nil
            case "--summary": summary = true
            case "--json": json = true
            default:
                print("Unknown option: \(arguments[index])")
                print("Usage: youxpc receipts [--last N] [--today] [--run ID] [--summary] [--json]")
                return
            }
            index += 1
        }

        guard let content = try? String(contentsOfFile: Receipts.path, encoding: .utf8) else {
            print("No receipts yet at \(Receipts.path)")
            return
        }
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        var events: [[String: Any]] = content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        if todayOnly { events = events.filter { ($0["time"] as? String)?.hasPrefix(today) == true } }
        if let runFilter { events = events.filter { $0["run"] as? String == runFilter } }

        if summary {
            printSummary(events)
            return
        }
        for event in events.suffix(max(1, limit)) {
            if json {
                if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
                   let line = String(data: data, encoding: .utf8)
                {
                    print(line)
                }
            } else {
                print(describe(event))
            }
        }
        if !json { print("\n\(events.count) event(s) in \(Receipts.path)") }
    }

    private func describe(_ event: [String: Any]) -> String {
        let time = (event["time"] as? String).map { String($0.dropFirst(11).prefix(8)) } ?? "--:--:--"
        let run = event["run"] as? String ?? "-"
        switch event["event"] as? String {
        case "server_start":
            let client = event["client"] as? String ?? "unknown"
            return "\(time) \(run)  server started for \(client) (v\(event["version"] as? String ?? "?"))"
        case "server_stop":
            return "\(time) \(run)  server stopped after \(event["calls"] as? Int ?? 0) call(s)"
        default:
            break
        }
        let tool = (event["tool"] as? String ?? "?").padding(toLength: 14, withPad: " ", startingAt: 0)
        let ok = (event["ok"] as? Bool ?? false) ? "ok  " : "FAIL"
        var parts: [String] = []
        if let app = event["app"] as? String { parts.append(app) }
        if let action = event["action"] as? String { parts.append(action) }
        if let index = event["index"] ?? event["n"] { parts.append("[\(index)]") }
        if let query = event["query"] as? String { parts.append("\"\(query)\"") }
        if let command = event["command"] as? String { parts.append("`\(command)`") }
        if let key = event["key"] as? String { parts.append("key \(key)") }
        if let element = event["element"] as? String {
            parts.append("-> \(element.replacingOccurrences(of: "\n", with: " / "))")
        }
        if let length = event["text_length"] as? Int { parts.append("typed \(length) chars") }
        if let text = event["text"] as? String { parts.append("typed \"\(text)\"") }
        if let pointer = event["pointer"] as? String { parts.append("pointer:\(pointer)") }
        if let changed = event["changed"] as? [String: Int] {
            parts.append("+\(changed["added"] ?? 0) -\(changed["removed"] ?? 0) ~\(changed["altered"] ?? 0)")
        }
        if let error = event["error"] as? String { parts.append("error: \(error)") }
        let ms = event["ms"] as? Int ?? 0
        return "\(time) \(run)  \(ok) \(tool) \(parts.joined(separator: "  "))  (\(ms)ms)"
    }

    private func printSummary(_ events: [[String: Any]]) {
        var days: [String: (calls: Int, failed: Int, runs: Set<String>, apps: Set<String>)] = [:]
        for event in events where event["event"] as? String == "tool" {
            let day = String((event["time"] as? String ?? "").prefix(10))
            var entry = days[day] ?? (0, 0, [], [])
            entry.calls += 1
            if event["ok"] as? Bool == false { entry.failed += 1 }
            if let run = event["run"] as? String { entry.runs.insert(run) }
            if let app = event["app"] as? String { entry.apps.insert(app) }
            days[day] = entry
        }
        print("day         calls  failed  runs  apps")
        for day in days.keys.sorted() {
            guard let entry = days[day] else { continue }
            let calls = String(entry.calls).padding(toLength: 6, withPad: " ", startingAt: 0)
            let failed = String(entry.failed).padding(toLength: 7, withPad: " ", startingAt: 0)
            let runs = String(entry.runs.count).padding(toLength: 5, withPad: " ", startingAt: 0)
            print("\(day)  \(calls) \(failed) \(runs) \(entry.apps.sorted().joined(separator: ", "))")
        }
    }
}
