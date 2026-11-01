import Foundation
import Testing
import TodoDomain
@testable import TodoPersistence

@Suite struct SQLiteStoreTests {
    private func withURL(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TodoDesktopTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder.appendingPathComponent("tasks.sqlite"))
    }
    @Test func freshStoreSeedsTypesAndReopens() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            #expect(try store.snapshot().categories.count == 4)
            var data = try store.snapshot()
            data.tasks = [.init(title: "持久化", scheduledDay: try LocalDate("2026-11-02"), scheduledMinute: 600, categoryID: data.categories[0].id)]
            data.countdowns = [.init(title: "发布", targetDay: try LocalDate("2026-11-12"))]
            try store.replace(with: data)
            try store.close()
            let reopened = try SQLiteStore(url: url)
            let loaded = try reopened.snapshot()
            #expect(loaded.tasks == data.tasks)
            #expect(loaded.countdowns == data.countdowns)
            try reopened.close()
        }
    }
    @Test func invalidRestoreLeavesExistingDataUntouched() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            var original = try store.snapshot()
            original.tasks = [.init(title: "不能丢失", scheduledDay: try LocalDate("2026-11-02"), scheduledMinute: 600, categoryID: original.categories[0].id)]
            try store.replace(with: original)
            var invalid = original; invalid.categories = []
            #expect(throws: (any Error).self) { try store.replace(with: invalid) }
            #expect(try store.snapshot().tasks == original.tasks)
            try store.close()
        }
    }
    @Test func sqliteSaveFailureRollsBack() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            var original = try store.snapshot()
            original.tasks = [.init(title: "原值", scheduledDay: try LocalDate("2026-11-02"), scheduledMinute: 600, categoryID: original.categories[0].id)]
            try store.replace(with: original); try store.close()
            let readOnly = try SQLiteStore(url: url, readOnly: true)
            var changed = try readOnly.snapshot(); changed.tasks[0].title = "禁止写入"
            #expect(throws: (any Error).self) { try readOnly.replace(with: changed) }
            #expect(try readOnly.snapshot().tasks[0].title == "原值")
            try readOnly.close()
        }
    }
    @Test func boundedQueryFindsMovedOverridesByBothDates() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            var data = try store.snapshot()
            let root = TodoSeries()
            let rule = TodoSeriesRule(seriesID: root.id, from: try LocalDate("2026-11-02"), title: "每天", minute: 600, categoryID: data.categories[0].id, frequency: .daily)
            data.series = [root]; data.rules = [rule]
            let projected = try AgendaCalculator.project(interval: .days(from: LocalDate("2026-11-02"), count: 1), tasks: [], series: data.series, rules: data.rules, exclusions: [], now: Date())
            var moved = try #require(projected.items.first)
            moved.scheduledDay = try LocalDate("2026-12-15"); moved.isOverride = true
            data.tasks = [moved]
            data.exclusions = [.init(seriesID: root.id, day: try LocalDate("2026-11-03"), reason: .userDeleted)]
            try store.replace(with: data)
            #expect(try store.agendaInput(in: .days(from: LocalDate("2026-11-02"), count: 1)).tasks.count == 1)
            #expect(try store.agendaInput(in: .days(from: LocalDate("2026-12-15"), count: 1)).tasks.count == 1)
            let loaded = try store.snapshot()
            #expect(loaded.rules[0].weekdays == rule.weekdays)
            #expect(loaded.exclusions[0].occurrenceKey == data.exclusions[0].occurrenceKey)
            try store.close()
        }
    }

    @Test func incrementalCommitPreservesUnrelatedRows() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            let day = try LocalDate("2026-11-02")
            let first = TodoItem(title: "第一条", scheduledDay: day, scheduledMinute: 540, categoryID: TodoCategory.defaults[0].id)
            let second = TodoItem(title: "第二条", scheduledDay: day, scheduledMinute: 600, categoryID: TodoCategory.defaults[0].id)
            var insert = StoreChanges(); insert.tasks = [first, second]
            try store.commit(insert)
            var updated = first; updated.title = "仅修改第一条"; updated.revision += 1
            var change = StoreChanges(); change.tasks = [updated]
            change.expectations = [.init(entity: .task, id: first.id, revision: 1)]
            try store.commit(change)
            #expect(try store.task(id: first.id)?.title == "仅修改第一条")
            #expect(try store.task(id: second.id) == second)
            try store.close()
        }
    }
    @Test func staleRevisionCannotOverwriteNewerValue() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            var item = TodoItem(title: "新版本", scheduledDay: try LocalDate("2026-11-02"), scheduledMinute: 540, categoryID: TodoCategory.defaults[0].id)
            item.revision = 2
            var insert = StoreChanges(); insert.tasks = [item]; try store.commit(insert)
            var stale = item; stale.title = "旧草稿覆盖"; stale.revision = 2
            var change = StoreChanges(); change.tasks = [stale]
            change.expectations = [.init(entity: .task, id: item.id, revision: 1)]
            #expect(throws: DomainError.conflict) { try store.commit(change) }
            #expect(try store.task(id: item.id)?.title == "新版本")
            try store.close()
        }
    }
    @Test func partialCategoryMigrationRollsBackEntireTransaction() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            let work = TodoCategory.defaults[1].id
            let day = try LocalDate("2026-11-02")
            var first = TodoItem(title: "一", scheduledDay: day, scheduledMinute: 540, categoryID: work)
            let second = TodoItem(title: "二", scheduledDay: day, scheduledMinute: 600, categoryID: work)
            var insert = StoreChanges(); insert.tasks = [first, second]; try store.commit(insert)
            first.categoryID = TodoCategory.defaults[0].id; first.revision += 1
            var migration = StoreChanges(); migration.tasks = [first]; migration.removals[.category] = [work]
            #expect(throws: (any Error).self) { try store.commit(migration) }
            #expect(try store.task(id: first.id)?.categoryID == work)
            #expect(try store.configuration().categories.count == 4)
            try store.close()
        }
    }
    @Test func duplicateOccurrenceSaveFailureKeepsOriginal() throws {
        try withURL { url in
            let store = try SQLiteStore(url: url)
            let root = TodoSeries()
            let rule = TodoSeriesRule(seriesID: root.id, from: try LocalDate("2026-11-02"), title: "原实例", minute: 540, categoryID: TodoCategory.defaults[0].id, frequency: .daily)
            let projection = try AgendaCalculator.project(interval: .days(from: LocalDate("2026-11-02"), count: 1), tasks: [], series: [root], rules: [rule], exclusions: [], now: Date())
            let original = try #require(projection.items.first)
            var insert = StoreChanges(); insert.series = [root]; insert.rules = [rule]; insert.tasks = [original]
            try store.commit(insert)
            var duplicate = original; duplicate.id = UUID(); duplicate.title = "重复不能覆盖"
            var bad = StoreChanges(); bad.tasks = [duplicate]
            #expect(throws: (any Error).self) { try store.commit(bad) }
            #expect(try store.snapshot().tasks == [original])
            try store.close()
        }
    }
}
