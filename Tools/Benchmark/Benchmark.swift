import Foundation
import Darwin
import TodoDomain
import TodoPersistence

struct Scenario: Codable {
    var tasks: Int, rules: Int, countdowns: Int
    var importMS: Double, openMS: Double, monthFirstMS: Double, cardMS: Double, farMonthMS: Double, saveMS: Double, exportMS: Double
    var monthVisible: Int, cardVisible: Int, farMonthVisible: Int, savedTasksAfterQueries: Int
    var exportBytes: Int, processPeakMB: Double
}
struct Report: Codable {
    var date: Date, system: String, architecture: String, processors: Int, build = "release"
    var scenarios: [Scenario]
}

@main struct Benchmark {
    static func measured<T>(_ body: () async throws -> T) async throws -> (T, Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await body()
        return (result, (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    static func fixture(taskCount: Int, ruleCount: Int, eventCount: Int, today: LocalDate) throws -> StoreSnapshot {
        var result = StoreSnapshot()
        for index in 0..<taskCount {
            var task = TodoItem(title: "基线任务 \(index)", scheduledDay: try today.adding(days: index % 60 - 29), scheduledMinute: index % 1440, categoryID: result.categories[index % 4].id)
            task.notes = String(repeating: "可控合成数据，用于测量本地查询。", count: 4)
            if task.scheduledDay < today { task.completedAt = today.noon() }
            result.tasks.append(task)
        }
        for index in 0..<ruleCount {
            let root = TodoSeries()
            let rule = TodoSeriesRule(seriesID: root.id, from: try today.adding(days: -29), title: "固定安排 \(index)", minute: index % 1440, categoryID: result.categories[index % 4].id, frequency: .weekly, weekdays: [1, 3, 5])
            result.series.append(root); result.rules.append(rule)
        }
        for index in 0..<eventCount { result.countdowns.append(CountdownEvent(title: "倒计时 \(index)", targetDay: try today.adding(days: index - 10))) }
        return result
    }
    static func run(tasks: Int, rules: Int, events: Int) async throws -> Scenario {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TodoBenchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("TodoDesktop.sqlite")
        let today = try LocalDate("2030-06-15"), clock = today.noon(timeZone: TimeZone(secondsFromGMT: 0)!)
        let snapshot = try fixture(taskCount: tasks, ruleCount: rules, eventCount: events, today: today)
        let initial = try TodoRepository(url: url, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
        let data = try SnapshotCodec.encode(snapshot)
        let (_, importMS) = try await measured { try await initial.restoreData(data) }
        try await initial.close()
        let (repo, openMS) = try await measured {
            let value = try TodoRepository(url: url, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
            _ = try await value.configuration(); return value
        }
        let (month, monthMS) = try await measured { try await repo.agenda(.month(containing: today), includeCompleted: true) }
        let (card, cardMS) = try await measured { try await repo.agenda(.days(from: today, count: 7)) }
        let (far, farMS) = try await measured { try await repo.agenda(.month(containing: LocalDate("2099-07-15")), includeCompleted: true) }
        let first = card.items.first!
        var edit = TaskDraft(task: first); edit.title = "基线保存验证"
        let (_, saveMS) = try await measured { try await repo.saveTask(edit) }
        let (exported, exportMS) = try await measured { try await repo.exportData() }
        let finalCount = try SnapshotCodec.decode(exported).tasks.count
        guard finalCount <= tasks + rules * 70, !far.items.isEmpty else { throw DomainError.invalidSnapshot("远期查询产生了无界展开") }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        try await repo.close()
        return Scenario(tasks: tasks, rules: rules, countdowns: events, importMS: importMS, openMS: openMS,
            monthFirstMS: monthMS, cardMS: cardMS, farMonthMS: farMS, saveMS: saveMS, exportMS: exportMS,
            monthVisible: month.items.count, cardVisible: card.items.count, farMonthVisible: far.items.count,
            savedTasksAfterQueries: finalCount, exportBytes: exported.count, processPeakMB: Double(usage.ru_maxrss) / 1048576)
    }
    static func main() async {
        do { try await runCommand() }
        catch {
            try? FileHandle.standardError.write(contentsOf: Data("TodoBenchmark: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }
    private static func runCommand() async throws {
        if let index = CommandLine.arguments.firstIndex(of: "--prepare-ui-fixture") {
            guard CommandLine.arguments.indices.contains(index + 1) else { throw DomainError.invalidSnapshot("缺少隔离验收标识") }
            let id = CommandLine.arguments[index + 1]
            guard id.range(of: "^[a-zA-Z0-9_-]{1,100}$", options: .regularExpression) != nil else { throw DomainError.invalidSnapshot("验收标识只允许ASCII字母、数字、横线和下划线") }
            let stress = CommandLine.arguments.contains("--stress")
            let counts = stress ? (10000, 100, 200) : (1000, 20, 50)
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/local.tododesktop.validation/Data/Library/Application Support/TodoDesktop-UITests/\(id)")
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw DomainError.invalidSnapshot("隔离目录已存在，拒绝覆盖；请使用新标识") }
            let snapshot = try fixture(taskCount: counts.0, ruleCount: counts.1, eventCount: counts.2, today: LocalDate(Date()))
            let repo = try TodoRepository(url: directory.appendingPathComponent("TodoDesktop.sqlite"))
            do {
                try await repo.restoreData(SnapshotCodec.encode(snapshot))
                let stored = try SnapshotCodec.decode(await repo.exportData())
                guard stored.tasks.count == counts.0, stored.series.count == counts.1, stored.countdowns.count == counts.2 else { throw DomainError.invalidSnapshot("样本数量不符") }
                try await repo.close()
                let metadata = ["tasks": counts.0, "rules": counts.1, "countdowns": counts.2]
                try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("fixture.json"), options: .atomic)
                print("Prepared isolated UI fixture: \(id), \(counts.0)/\(counts.1)/\(counts.2)")
            } catch { try? await repo.close(); throw error }
            return
        }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        var results: [Scenario] = []
        for (tasks, rules, events) in [(1000, 20, 50), (10000, 100, 200)] { results.append(try await run(tasks: tasks, rules: rules, events: events)) }
        let report = Report(date: Date(), system: ProcessInfo.processInfo.operatingSystemVersionString, architecture: architecture,
                            processors: ProcessInfo.processInfo.processorCount, scenarios: results)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        if let index = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.indices.contains(index + 1) {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
    }
}
