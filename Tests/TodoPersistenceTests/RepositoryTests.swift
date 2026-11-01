import Foundation
import Testing
import TodoDomain
@testable import TodoPersistence

@Suite struct RepositoryTests {
    private var clock: Date { ISO8601DateFormatter().date(from: "2026-11-02T08:00:00Z")! }
    private func d(_ value: String) throws -> LocalDate { try LocalDate(value) }
    private func draft(_ title: String = "阅读", day: String = "2026-11-02", repeating: RepeatFrequency? = nil) throws -> TaskDraft {
        var value = TaskDraft(day: try d(day)); value.title = title; value.minute = 540
        value.categoryID = TodoCategory.defaults[2].id; value.frequency = repeating
        value.weekdays = [1, 3]
        return value
    }
    private func withRepository(_ body: (TodoRepository, URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TodoRepositoryTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tasks.sqlite")
        let instant = clock
        let repository = try TodoRepository(url: url, now: { instant }, timeZone: { TimeZone(secondsFromGMT: 0)! })
        do { try await body(repository, url); try await repository.close() }
        catch { try? await repository.close(); throw error }
    }

    @Test func taskCRUDAndReopenUsesRealStore() async throws {
        try await withRepository { repo, url in
            let created = try await repo.saveTask(draft())
            let first = try await repo.agenda(.days(from: d("2026-11-02"), count: 1))
            #expect(first.items.count == 1)
            var edit = TaskDraft(task: created.task); edit.title = "已编辑"; edit.minute = 600
            let saved = try await repo.saveTask(edit)
            #expect(saved.task.revision == 2)
            try await repo.close()
            let reopened = try TodoRepository(url: url)
            #expect(try await reopened.task(id: saved.task.id) == saved.task)
            try await reopened.close()
        }
    }
    @Test func requiredFieldsAreNotBypassedByRepository() async throws {
        try await withRepository { repo, _ in
            var value = try draft(); value.minute = -2
            await #expect(throws: DomainError.invalidTime) { try await repo.saveTask(value) }
            value = try draft(); value.categoryID = nil
            await #expect(throws: DomainError.missingCategory) { try await repo.saveTask(value) }
            value = try draft(); value.title = "  "
            await #expect(throws: DomainError.emptyTitle) { try await repo.saveTask(value) }
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 1)).items.isEmpty)
        }
    }
    @Test func optionalTimeSurvivesSQLiteBackupAndTimeEdits() async throws {
        try await withRepository { repo, url in
            let timed = try await repo.saveTask(draft("已有时间")).task
            var noTime = try draft("日期待办"); noTime.minute = nil
            noTime.notes = "保留备注"; noTime.reminderAt = clock.addingTimeInterval(3600)
            let saved = try await repo.saveTask(noTime).task
            #expect(!saved.hasScheduledTime && saved.timeLabel.isEmpty)
            #expect(TaskDraft(task: saved).minute == nil)
            var clear = TaskDraft(task: timed); clear.minute = nil
            let cleared = try await repo.saveTask(clear).task
            #expect(cleared.id == timed.id && !cleared.hasScheduledTime)
            var restore = TaskDraft(task: cleared); restore.minute = 0
            let midnight = try await repo.saveTask(restore).task
            #expect(midnight.id == timed.id && midnight.timeLabel == "00:00")
            let backup = try await repo.exportData()
            let decoded = try SnapshotCodec.decode(backup)
            #expect(decoded.tasks.first { $0.id == saved.id } == saved)
            try await repo.restoreData(backup)
            try await repo.close()
            let reopened = try TodoRepository(url: url)
            #expect(try await reopened.task(id: saved.id) == saved)
            #expect(try await reopened.task(id: midnight.id) == midnight)
            try await reopened.close()
        }
    }
    @Test func untimedDailyAndWeeklyInstancesRemainIndependent() async throws {
        try await withRepository { repo, _ in
            for frequency in [RepeatFrequency.daily, .weekly] {
                var value = try draft(frequency.rawValue, repeating: frequency); value.minute = nil
                let first = try await repo.saveTask(value).task
                let range = try await repo.agenda(.days(from: d("2026-11-02"), count: 3))
                let instances = range.items.filter { $0.seriesID == first.seriesID }
                #expect(instances.count == (frequency == .daily ? 3 : 2))
                #expect(instances.allSatisfy { !$0.hasScheduledTime && $0.reminderAt == nil })
                _ = try await repo.setCompletion(id: first.id, completed: true)
                let next = try await repo.agenda(.days(from: d("2026-11-03"), count: 2))
                #expect(next.items.contains { $0.seriesID == first.seriesID && $0.completedAt == nil && !$0.hasScheduledTime })
            }
            let before = try await repo.exportData()
            #expect(try await repo.rolloverUnfinishedSingles() == 0)
            #expect(try await repo.exportData() == before)
        }
    }
    @Test func untimedRolloverPreservesExplicitReminderAndIdentity() async throws {
        try await withRepository { repo, _ in
            var value = try draft("顺延", day: "2026-10-30"); value.minute = nil
            value.reminderAt = clock.addingTimeInterval(3600)
            let original = try await repo.saveTask(value).task
            #expect(try await repo.rolloverUnfinishedSingles() == 1)
            let moved = try #require(await repo.task(id: original.id))
            #expect(moved.scheduledDay == (try d("2026-11-02")) && !moved.hasScheduledTime)
            #expect(moved.reminderAt == original.reminderAt)
            #expect(try await repo.reminderCandidates().tasks.first?.id == original.id)
            _ = try await repo.setCompletion(id: original.id, completed: true)
            #expect(try await repo.reminderCandidates().tasks.isEmpty)
        }
    }
    @Test func untimedRelativeReminderRejectsWithoutWriting() async throws {
        try await withRepository { repo, _ in
            var value = try draft(repeating: .daily); value.minute = nil; value.reminderOffsetMinutes = 0
            await #expect(throws: DomainError.recurringReminderNeedsTime) { try await repo.saveTask(value) }
            let snapshot = try SnapshotCodec.decode(await repo.exportData())
            #expect(snapshot.tasks.isEmpty && snapshot.rules.isEmpty && snapshot.series.isEmpty)
        }
    }
    @Test func countdownEditArchiveDeleteUndoPreservesContentsAndRejectsStaleUndo() async throws {
        try await withRepository { repo, _ in
            var draft = CountdownDraft(day: try d("2027-01-01")); draft.title = "新年"; draft.notes = "原备注"
            let original = try await repo.saveCountdown(draft)
            draft = CountdownDraft(event: original); draft.title = "假期"; draft.day = try d("2027-01-02")
            let edit = try #require(await repo.saveCountdownWithUndo(draft).undo)
            let archive = try #require(await repo.setCountdownState(id: original.id, archived: true))
            let deletion = try #require(await repo.setCountdownState(id: original.id, deleted: true))
            #expect(try await repo.countdowns().isEmpty)
            try await repo.undo(deletion)
            #expect(try await repo.countdowns(archived: true).first?.title == "假期")
            let rebasedArchive = archive.rebased(after: deletion)
            try await repo.undo(rebasedArchive)
            let rebasedEdit = edit.rebased(after: deletion).rebased(after: rebasedArchive)
            try await repo.undo(rebasedEdit)
            let restored = try #require(await repo.countdown(id: original.id))
            #expect(restored.title == original.title && restored.notes == original.notes && restored.targetDay == original.targetDay)
            #expect(restored.archivedAt == nil && restored.deletedAt == nil && restored.revision == 7)
            await #expect(throws: DomainError.conflict) { try await repo.undo(edit) }
            var newer = CountdownDraft(event: restored); newer.title = "其他窗口修改"
            _ = try await repo.saveCountdown(newer)
            await #expect(throws: DomainError.conflict) { try await repo.undo(rebasedEdit) }
            #expect(try await repo.countdown(id: original.id)?.title == "其他窗口修改")
        }
    }
    @Test func sequentialTaskUndoFollowsOnlyItsOwnRevisionChain() async throws {
        try await withRepository { repo, _ in
            let original = try await repo.saveTask(draft()).task
            var changed = TaskDraft(task: original); changed.title = "新标题"
            let edit = try #require(await repo.saveTask(changed).undo)
            let completion = try #require(await repo.setCompletion(id: original.id, completed: true))
            try await repo.undo(completion)
            let rebased = edit.rebased(after: completion)
            try await repo.undo(rebased)
            let restored = try #require(await repo.task(id: original.id))
            #expect(restored.title == original.title && restored.completedAt == nil && restored.revision == 5)
            await #expect(throws: DomainError.conflict) { try await repo.undo(rebased) }
        }
    }
    @Test func deletedCountdownCannotBeArchivedOrEditedByStaleCommands() async throws {
        try await withRepository { repo, _ in
            var draft = CountdownDraft(day: try d("2027-01-01")); draft.title = "旅行"
            let original = try await repo.saveCountdown(draft)
            _ = try await repo.setCountdownState(id: original.id, deleted: true)
            await #expect(throws: DomainError.notFound) { try await repo.setCountdownState(id: original.id, archived: true) }
            let deleted = try #require(await repo.countdown(id: original.id))
            await #expect(throws: DomainError.notFound) { try await repo.saveCountdown(CountdownDraft(event: deleted)) }
            #expect(try await repo.setCountdownState(id: original.id, deleted: false) == nil)
            #expect(try await repo.countdowns().first?.id == original.id)
        }
    }
    @Test func dailyCompletionUndoAndRequeryAreIndependent() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft(repeating: .daily))
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 7)).items.count == 7)
            let action = try #require(await repo.setCompletion(id: saved.task.id, completed: true))
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 7)).items.count == 6)
            #expect(try await repo.completed().items.count == 1)
            #expect(try await repo.setCompletion(id: saved.task.id, completed: true) == nil)
            try await repo.undo(action)
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 7)).items.count == 7)
            #expect(try await repo.completed().items.isEmpty)
        }
    }
    @Test func singleOverrideMovesWithoutRegeneratingOriginal() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft(repeating: .daily))
            let config = try await repo.configuration()
            var edit = TaskDraft(task: saved.task, rule: config.rules[0], series: config.series[0]); edit.day = try d("2026-11-03")
            _ = try await repo.saveTask(edit)
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 1)).items.isEmpty)
            let tomorrow = try await repo.agenda(.days(from: d("2026-11-03"), count: 1))
            #expect(tomorrow.items.count == 2)
            #expect(tomorrow.items.filter { $0.id == saved.task.id }.count == 1)
        }
    }
    @Test func quickMoveUsesLocalTomorrowAndPreservesFieldsAndUndo() async throws {
        try await withRepository { repo, _ in
            var value = try draft(day: "2026-12-20")
            value.notes = "保留备注"; value.isImportant = true; value.reminderAt = self.clock.addingTimeInterval(3600)
            let original = try await repo.saveTask(value).task
            let moved = try await repo.quickEditTask(id: original.id, baseRevision: original.revision, change: .moveToTomorrow)
            #expect(moved.task.scheduledDay == (try d("2026-11-03")))
            #expect(moved.task.id == original.id)
            #expect(moved.task.title == original.title && moved.task.notes == original.notes)
            #expect(moved.task.scheduledMinute == original.scheduledMinute && moved.task.categoryID == original.categoryID)
            #expect(moved.task.reminderAt == original.reminderAt && moved.task.isImportant)
            let undo = try #require(moved.undo)
            try await repo.undo(undo)
            let restored = try #require(await repo.task(id: original.id))
            #expect(restored.scheduledDay == original.scheduledDay)
            #expect(restored.notes == original.notes && restored.reminderAt == original.reminderAt)
        }
    }
    @Test func quickImportanceAffectsOnlyOccurrenceAndRejectsStaleRevision() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            let result = try await repo.quickEditTask(id: first.id, baseRevision: first.revision, change: .setImportant(true))
            #expect(result.task.isOverride && result.task.isImportant)
            #expect(result.task.seriesID == first.seriesID && result.task.occurrenceDay == first.occurrenceDay)
            let all = try await repo.agenda(.days(from: d("2026-11-02"), count: 3)).items
            #expect(all.filter(\.isImportant).map(\.id) == [first.id])
            let unchanged = try await repo.quickEditTask(id: first.id, baseRevision: result.task.revision, change: .setImportant(true))
            #expect(unchanged.undo == nil && unchanged.task.revision == result.task.revision)
            await #expect(throws: DomainError.conflict) {
                try await repo.quickEditTask(id: first.id, baseRevision: first.revision, change: .setImportant(false))
            }
        }
    }
    @Test func quickMoveKeepsOriginalOccurrenceAndCompletedState() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            _ = try await repo.setCompletion(id: first.id, completed: true)
            let completed = try #require(await repo.task(id: first.id))
            let result = try await repo.quickEditTask(id: first.id, baseRevision: completed.revision, change: .moveToTomorrow)
            #expect(result.task.completedAt == completed.completedAt)
            #expect(result.task.occurrenceDay == (try d("2026-11-02")))
            #expect(result.task.scheduledDay == (try d("2026-11-03")))
            let all = try await repo.agenda(.days(from: d("2026-11-02"), count: 2), includeCompleted: true).items
            #expect(all.count == 2)
            #expect(all.filter { $0.id == first.id }.count == 1)
            _ = try await repo.deleteTask(id: first.id)
            await #expect(throws: DomainError.notFound) {
                try await repo.quickEditTask(id: first.id, baseRevision: result.task.revision, change: .setImportant(true))
            }
        }
    }
    @Test func upcomingPreviewHonorsVersionsSkipsAndMovedExceptionsWithoutWriting() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            let all = try await repo.agenda(.days(from: d("2026-11-02"), count: 14)).items
            _ = try await repo.setCompletion(id: first.id, completed: true)
            let moved = try #require(all.first { $0.scheduledDay == (try? d("2026-11-03")) })
            var exception = TaskDraft(task: moved); exception.day = try d("2026-11-08"); exception.title = "改期例外"
            _ = try await repo.saveTask(exception)
            let deleted = try #require(all.first { $0.scheduledDay == (try? d("2026-11-04")) })
            _ = try await repo.deleteTask(id: deleted.id)
            let cut = try #require(all.first { $0.scheduledDay == (try? d("2026-11-09")) })
            let config = try await repo.configuration()
            var update = TaskDraft(task: cut, rule: config.rules[0], series: config.series[0]); update.scope = .thisAndFollowing; update.title = "新版本"
            _ = try await repo.saveTask(update)
            let before = try SnapshotCodec.decode(await repo.exportData())
            let preview = try await repo.upcomingSeries(id: first.seriesID!, from: d("2026-11-02"), limit: 8)
            #expect(Array(preview.prefix(3).map(\.day)) == (try [d("2026-11-05"), d("2026-11-06"), d("2026-11-07")]))
            #expect(preview.contains { $0.id == moved.id && $0.isOverride && $0.originalDay == (try? d("2026-11-03")) })
            #expect(preview.first { $0.day == (try? d("2026-11-09")) }?.title == "新版本")
            let after = try SnapshotCodec.decode(await repo.exportData())
            #expect(after.tasks == before.tasks && after.rules == before.rules && after.exclusions == before.exclusions)
        }
    }
    @Test func reviewRejectsChangedExceptionAndNewMaterialization() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            let all = try await repo.agenda(.days(from: d("2026-11-02"), count: 3)).items
            let review = try await repo.reviewSeries(id: first.seriesID!, from: d("2026-11-02"), change: .update(selectedID: first.id))
            let later = try #require(all.last)
            _ = try await repo.quickEditTask(id: later.id, baseRevision: later.revision, change: .setImportant(true))
            let config = try await repo.configuration()
            var update = TaskDraft(task: first, rule: config.rules[0], series: config.series[0]); update.scope = .thisAndFollowing; update.title = "批量修改"
            await #expect(throws: DomainError.conflict) { try await repo.saveTask(update, reviewed: review) }
            let fresh = try await repo.reviewSeries(id: first.seriesID!, from: d("2026-11-02"), change: .update(selectedID: first.id))
            #expect(fresh.affectedCount == 2 && fresh.exceptions.count == 1)
            _ = try await repo.saveTask(update, reviewed: fresh)
            let stop = try await repo.reviewSeries(id: first.seriesID!, from: d("2026-11-02"), change: .stop)
            _ = try await repo.agenda(.days(from: d("2026-11-02"), count: 14))
            await #expect(throws: DomainError.conflict) {
                try await repo.stopSeries(id: first.seriesID!, from: d("2026-11-02"), baseRevision: stop.seriesRevision, reviewed: stop)
            }
            #expect(try await repo.configuration().series[0].stoppedFromDay == nil)
        }
    }
    @Test func stoppedSeriesPreviewKeepsEarlierMovedOccurrenceAndCopyIsIndependent() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            let config = try await repo.configuration()
            var moved = TaskDraft(task: first); moved.day = try d("2026-11-10")
            _ = try await repo.saveTask(moved)
            _ = try await repo.stopSeries(id: first.seriesID!, from: d("2026-11-03"), baseRevision: config.series[0].revision)
            let preview = try await repo.upcomingSeries(id: first.seriesID!, from: d("2026-11-04"))
            #expect(preview.map(\.id) == [first.id])
            let copied = TaskDraft(copying: config.rules[0], starting: try d("2026-11-06"))
            let saved = try await repo.saveTask(copied).task
            #expect(saved.seriesID != first.seriesID && saved.id != first.id)
            #expect(try await repo.configuration().series.first { $0.id == first.seriesID }?.stoppedFromDay == (try d("2026-11-03")))
            #expect(try await repo.agenda(.days(from: d("2026-11-04"), count: 1)).items.isEmpty)
        }
    }
    @Test func farUpcomingPreviewDoesNotExpandInterveningYears() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(day: "9999-12-30", repeating: .daily)).task
            let preview = try await repo.upcomingSeries(id: first.seriesID!, from: d("2026-11-02"))
            #expect(preview.map(\.day) == (try [d("9999-12-30"), d("9999-12-31")]))
            #expect(try SnapshotCodec.decode(await repo.exportData()).tasks.count == 1)
        }
    }
    @Test func forwardRuleEditPreservesHistoryAndFutureOverrides() async throws {
        try await withRepository { repo, _ in
            _ = try await repo.saveTask(draft(repeating: .weekly))
            let all = try await repo.agenda(.days(from: d("2026-11-02"), count: 14))
            let monday = try #require(all.items.first { $0.scheduledDay == (try? d("2026-11-02")) })
            _ = try await repo.setCompletion(id: monday.id, completed: true)
            var config = try await repo.configuration()
            let nextMonday = try #require(all.items.first { $0.scheduledDay == (try? d("2026-11-09")) })
            var exception = TaskDraft(task: nextMonday, rule: config.rules[0], series: config.series[0]); exception.day = try d("2026-11-10")
            _ = try await repo.saveTask(exception)
            let wednesday = try #require(all.items.first { $0.scheduledDay == (try? d("2026-11-04")) })
            var update = TaskDraft(task: wednesday, rule: config.rules[0], series: config.series[0])
            update.scope = .thisAndFollowing; update.minute = 600; update.title = "新安排"
            _ = try await repo.saveTask(update)
            let result = try await repo.agenda(.days(from: d("2026-11-02"), count: 14), includeCompleted: true)
            #expect(result.items.first { $0.id == monday.id }?.title == "阅读")
            #expect(result.items.first { $0.id == wednesday.id }?.scheduledMinute == 600)
            #expect(result.items.first { $0.id == nextMonday.id }?.scheduledDay == (try d("2026-11-10")))
            config = try await repo.configuration()
            #expect(config.rules.count == 2)
        }
    }
    @Test func staleCompletionCannotReviveAnOccurrenceSuppressedByStoppingItsSeries() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.saveTask(draft(repeating: .daily)).task
            let config = try await repo.configuration()
            let action = try await repo.stopSeries(id: first.seriesID!, from: first.scheduledDay, baseRevision: config.series[0].revision)
            await #expect(throws: DomainError.notFound) { try await repo.setCompletion(id: first.id, completed: true) }
            #expect(try await repo.agenda(.days(from: first.scheduledDay, count: 1), includeCompleted: true).items.isEmpty)
            #expect(try await repo.completed().items.isEmpty)
            // The rejected stale click must not change revisions or break the real undo.
            try await repo.undo(action)
            let restored = try #require(await repo.agenda(.days(from: first.scheduledDay, count: 1)).items.first)
            #expect(restored.id == first.id && restored.completedAt == nil)
        }
    }
    @Test func stopAndUndoRetainCompletedHistory() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft(repeating: .daily))
            _ = try await repo.agenda(.days(from: d("2026-11-02"), count: 7))
            _ = try await repo.setCompletion(id: saved.task.id, completed: true)
            let config = try await repo.configuration()
            let action = try await repo.stopSeries(id: config.series[0].id, from: d("2026-11-02"), baseRevision: config.series[0].revision)
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 7)).items.isEmpty)
            #expect(try await repo.completed().items.count == 1)
            try await repo.undo(action)
            #expect(try await repo.agenda(.days(from: d("2026-11-02"), count: 7)).items.count == 6)
        }
    }
    @Test func stopFromOriginalDaySuppressesMovedFutureButKeepsEarlierAndCompleted() async throws {
        try await withRepository { repo, _ in
            _ = try await repo.saveTask(draft(repeating: .daily))
            let interval = try DayInterval.days(from: d("2026-11-02"), count: 7)
            let all = try await repo.agenda(interval).items
            let config = try await repo.configuration()
            let moved = try #require(all.first { $0.scheduledDay == (try? d("2026-11-04")) })
            let completed = try #require(all.first { $0.scheduledDay == (try? d("2026-11-05")) })
            var change = TaskDraft(task: moved, rule: config.rules[0], series: config.series[0])
            change.day = try d("2026-11-08")
            _ = try await repo.saveTask(change)
            _ = try await repo.setCompletion(id: completed.id, completed: true)
            let action = try await repo.stopSeries(id: config.series[0].id, from: d("2026-11-04"), baseRevision: config.series[0].revision)
            let stopped = try await repo.agenda(interval, includeCompleted: true).items
            #expect(stopped.count == 3)
            #expect(stopped.filter { $0.completedAt == nil }.map(\.scheduledDay) == [try d("2026-11-02"), try d("2026-11-03")])
            #expect(stopped.contains { $0.id == completed.id && $0.completedAt != nil })
            #expect(!stopped.contains { $0.id == moved.id })
            try await repo.undo(action)
            let restored = try await repo.agenda(interval, includeCompleted: true).items
            #expect(restored.count == 7)
            #expect(restored.first { $0.id == moved.id }?.scheduledDay == (try d("2026-11-08")))
            #expect(restored.first { $0.id == completed.id }?.completedAt != nil)
        }
    }
    @Test func deletingOccurrenceStillExcludesItAfterPurge() async throws {
        try await withRepository { repo, url in
            let saved = try await repo.saveTask(draft(repeating: .daily))
            _ = try await repo.deleteTask(id: saved.task.id)
            try await repo.close()
            let later = ISO8601DateFormatter().date(from: "2026-12-10T08:00:00Z")!
            let reopened = try TodoRepository(url: url, now: { later })
            try await reopened.purgeExpiredTrash()
            #expect(try await reopened.task(id: saved.task.id) == nil)
            #expect(try await reopened.agenda(.days(from: d("2026-11-02"), count: 1)).items.isEmpty)
            #expect(try await reopened.configuration().exclusions.count == 1)
            try await reopened.close()
        }
    }
    @Test func categoryReplacementMigratesRulesAndCompletedInstances() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft(repeating: .daily))
            _ = try await repo.setCompletion(id: saved.task.id, completed: true)
            let config = try await repo.configuration()
            let old = try #require(config.categories.first { $0.id == saved.task.categoryID })
            let replacement = TodoCategory.defaults[1].id
            try await repo.replaceCategory(id: old.id, with: replacement, baseRevision: old.revision)
            #expect(try await repo.completed().items[0].categoryID == replacement)
            #expect(try await repo.configuration().rules[0].categoryID == replacement)
            #expect(try await repo.agenda(.days(from: d("2026-11-03"), count: 1)).items[0].categoryID == replacement)
        }
    }
    @Test func staleDraftAndStaleUndoDoNotOverwriteEdits() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft())
            var edit = TaskDraft(task: saved.task); edit.title = "新的标题"
            let updated = try await repo.saveTask(edit)
            edit.title = "旧草稿"
            await #expect(throws: DomainError.conflict) { try await repo.saveTask(edit) }
            var newest = TaskDraft(task: updated.task); newest.minute = 720
            _ = try await repo.saveTask(newest)
            let action = try #require(updated.undo)
            await #expect(throws: DomainError.conflict) { try await repo.undo(action) }
            #expect(try await repo.task(id: saved.task.id)?.scheduledMinute == 720)
        }
    }
    @Test func completedCursorCoversEqualTimestampsWithoutDuplicates() async throws {
        try await withRepository { repo, _ in
            for index in 0..<63 {
                let saved = try await repo.saveTask(draft("历史 \(index)"))
                _ = try await repo.setCompletion(id: saved.task.id, completed: true)
            }
            let first = try await repo.completed()
            let second = try await repo.completed(after: first.nextCursor)
            #expect(first.items.count == 50)
            #expect(second.items.count == 13)
            #expect(Set((first.items + second.items).map(\.id)).count == 63)
            #expect(second.nextCursor == nil)
        }
    }
    @Test func countdownValidationArchiveAndSnapshotRestore() async throws {
        try await withRepository { repo, _ in
            var value = CountdownDraft(day: try d("2026-11-12")); value.title = "发布"
            let saved = try await repo.saveCountdown(value)
            let backup = try await repo.exportData()
            try await repo.setCountdownState(id: saved.id, archived: true)
            #expect(try await repo.countdowns().isEmpty)
            #expect(try await repo.countdowns(archived: true).count == 1)
            try await repo.restoreData(backup)
            #expect(try await repo.countdowns()[0].id == saved.id)
            var invalid = CountdownDraft(day: try d("2026-11-12")); invalid.title = ""
            await #expect(throws: DomainError.emptyTitle) { try await repo.saveCountdown(invalid) }
            await #expect(throws: (any Error).self) { try await repo.restoreData(Data("{bad}".utf8)) }
            #expect(try await repo.countdowns().count == 1)
        }
    }
    @Test func countdownReeditUsesFreshRevisionAndDeletedDraftCanOnlyCreateNewIdentity() async throws {
        try await withRepository { repo, _ in
            var initial = CountdownDraft(day: try d("2026-11-12")); initial.title = "初始事件"
            let old = try await repo.saveCountdown(initial)
            var savedDraft = CountdownDraft(event: old); savedDraft.title = "离开前保存"
            let saved = try await repo.saveCountdown(savedDraft)
            let latest = try #require(await repo.countdown(id: old.id))
            #expect(latest == saved && latest.revision == 2)
            await #expect(throws: DomainError.conflict) { try await repo.saveCountdown(CountdownDraft(event: old)) }
            var editingAgain = CountdownDraft(event: latest); editingAgain.notes = "再次编辑保留新标题"
            _ = try await repo.saveCountdown(editingAgain)
            try await repo.setCountdownState(id: old.id, archived: true)
            #expect(try await repo.countdown(id: old.id)?.archivedAt != nil)
            try await repo.setCountdownState(id: old.id, deleted: true)
            let deleted = try #require(await repo.countdown(id: old.id))
            await #expect(throws: DomainError.notFound) { try await repo.saveCountdown(CountdownDraft(event: deleted)) }
            var copy = CountdownDraft(event: deleted); copy.id = UUID(); copy.baseRevision = 0
            let created = try await repo.saveCountdown(copy)
            #expect(created.id != old.id && created.title == "离开前保存" && created.notes == "再次编辑保留新标题")
            #expect(created.deletedAt == nil && created.archivedAt == nil)
            #expect(try await repo.countdown(id: old.id)?.deletedAt != nil)
            #expect(try await repo.countdowns().count == 1)
        }
    }
    @Test func concurrentDraftSavesHaveOneWinner() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft())
            let wins = await withTaskGroup(of: Bool.self) { group in
                for index in 0..<20 {
                    group.addTask {
                        var edit = TaskDraft(task: saved.task); edit.title = "编辑 \(index)"
                        do { _ = try await repo.saveTask(edit); return true }
                        catch { return false }
                    }
                }
                var count = 0
                for await success in group { if success { count += 1 } }
                return count
            }
            #expect(wins == 1)
            #expect(try await repo.task(id: saved.task.id)?.revision == 2)
        }
    }
    @Test func singleToWeeklyAndBackKeepsOneTaskIdentity() async throws {
        try await withRepository { repo, _ in
            let original = try await repo.saveTask(draft())
            var repeating = TaskDraft(task: original.task); repeating.frequency = .weekly; repeating.weekdays = [3]
            let fixed = try await repo.saveTask(repeating)
            #expect(fixed.task.id == original.task.id)
            #expect(fixed.task.scheduledDay == (try d("2026-11-04")))
            let config = try await repo.configuration()
            var detached = TaskDraft(task: fixed.task, rule: config.rules[0], series: config.series[0])
            detached.scope = .thisAndFollowing; detached.frequency = nil
            let single = try await repo.saveTask(detached)
            #expect(single.task.seriesID == nil)
            #expect(try await repo.agenda(.days(from: d("2026-11-04"), count: 7)).items.count == 1)
        }
    }
    @Test func maximumDateDoesNotRequireSevenDaysOfLookahead() async throws {
        try await withRepository { repo, _ in
            _ = try await repo.saveTask(draft(day: "9999-12-31", repeating: .daily))
            #expect(try await repo.agenda(.days(from: d("9999-12-31"), count: 1)).items.count == 1)
        }
    }

    @Test func completedStaysInScheduleButLeavesCardAndCanBeReopened() async throws {
        try await withRepository { repo, _ in
            let saved = try await repo.saveTask(draft())
            _ = try await repo.setCompletion(id: saved.task.id, completed: true)
            let day = try d("2026-11-02")
            let card = try await repo.agenda(.days(from: day, count: 7))
            #expect(card.items.isEmpty)
            let week = try await repo.agenda(.week(containing: day), includeCompleted: true)
            let month = try await repo.agenda(.month(containing: day), includeCompleted: true)
            #expect(week.items.map(\.id) == [saved.task.id])
            #expect(month.items.map(\.id) == [saved.task.id])
            #expect(month.items[0].completedAt != nil)
            #expect(month.items[0].scheduledMinute == 540)
            _ = try await repo.setCompletion(id: saved.task.id, completed: false)
            #expect(try await repo.agenda(.days(from: day, count: 7)).items.map(\.id) == [saved.task.id])
        }
    }

    @Test func remindersUseFiniteHorizonAndRecomputeLocalRuleTimeAfterTravel() async throws {
        try await withRepository { repo, url in
            var repeating = try draft(repeating: .daily); repeating.reminderOffsetMinutes = 0
            let saved = try await repo.saveTask(repeating)
            var single = try draft("独立提醒"); single.reminderAt = clock.addingTimeInterval(7200)
            let absolute = try await repo.saveTask(single)
            var event = CountdownDraft(day: try d("2050-01-01")); event.title = "远期事件"
            event.reminderAt = ISO8601DateFormatter().date(from: "2050-01-01T01:00:00Z")!
            _ = try await repo.saveCountdown(event)
            try await repo.close()
            let instant = clock
            let traveled = try TodoRepository(url: url, now: { instant }, timeZone: { TimeZone(identifier: "America/Los_Angeles")! })
            let candidates = try await traveled.reminderCandidates()
            #expect(candidates.tasks.count == 31)
            let local = try #require(candidates.tasks.first { $0.id == saved.task.id })
            #expect(local.reminderAt == ISO8601DateFormatter().date(from: "2026-11-02T17:00:00Z"))
            #expect(candidates.tasks.first { $0.id == absolute.task.id }?.reminderAt == single.reminderAt)
            #expect(candidates.events.count == 1)
            try await traveled.close()
        }
    }

    @Test func halfHourGapRuleReminderUsesSameDayLegalInstant() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HalfHourReminder-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        let zone = TimeZone(identifier: "Australia/Lord_Howe")!
        let repo = try TodoRepository(url: folder.appendingPathComponent("tasks.sqlite"), now: { clock }, timeZone: { zone })
        do {
            var value = try draft("半小时变化", day: "2026-10-04", repeating: .weekly)
            value.weekdays = [7]; value.minute = 135; value.reminderOffsetMinutes = 0
            let saved = try await repo.saveTask(value).task
            // 02:15 is missing: the first legal instant is 02:30 UTC+11,
            // not 02:15 on the following civil date.
            let expected = ISO8601DateFormatter().date(from: "2026-10-03T15:30:00Z")!
            #expect(saved.scheduledDay == (try d("2026-10-04")) && saved.scheduledMinute == 135)
            #expect(saved.reminderAt == expected)
            let candidates = try await repo.reminderCandidates()
            #expect(candidates.tasks.first { $0.id == saved.id }?.reminderAt == expected)
            #expect(candidates.tasks.filter { $0.id == saved.id }.count == 1)
            try await repo.close()
        } catch { try? await repo.close(); throw error }
    }

    @Test func rolloverOnlyMovesOpenOneOffsAndKeepsTheirIdentityAndFields() async throws {
        try await withRepository { repo, _ in
            var value = try draft("未完成单次", day: "2026-11-01")
            value.notes = "保留备注"; value.isImportant = true
            value.reminderAt = clock.addingTimeInterval(3600)
            let moving = try await repo.saveTask(value).task
            let completed = try await repo.saveTask(draft("已完成", day: "2026-11-01")).task
            _ = try await repo.setCompletion(id: completed.id, completed: true)
            let deleted = try await repo.saveTask(draft("已删除", day: "2026-11-01")).task
            _ = try await repo.deleteTask(id: deleted.id)
            let today = try await repo.saveTask(draft("今天")).task
            let future = try await repo.saveTask(draft("未来", day: "2026-11-04")).task
            let fixed = try await repo.saveTask(draft("每日", repeating: .daily)).task
            var snapshot = try SnapshotCodec.decode(await repo.exportData())
            let past = try d("2026-11-01")
            snapshot.rules[0].effectiveFromDay = past
            let projection = try AgendaCalculator.project(interval: .days(from: past, count: 1), tasks: snapshot.tasks,
                series: snapshot.series, rules: snapshot.rules, exclusions: [], now: clock, timeZone: TimeZone(secondsFromGMT: 0)!)
            snapshot.tasks += projection.missingInstances
            try await repo.restoreData(SnapshotCodec.encode(snapshot))
            let recurringPast = try #require(projection.items.first { $0.seriesID != nil })
            #expect(try await repo.rolloverUnfinishedSingles() == 1)
            let result = try #require(await repo.task(id: moving.id))
            #expect(result.scheduledDay == (try d("2026-11-02")))
            #expect(result.title == moving.title && result.notes == moving.notes)
            #expect(result.scheduledMinute == moving.scheduledMinute && result.categoryID == moving.categoryID)
            #expect(result.isImportant && result.reminderAt == moving.reminderAt)
            #expect(result.revision == moving.revision + 1)
            #expect(try await repo.task(id: recurringPast.id)?.scheduledDay == past)
            #expect(try await repo.task(id: completed.id)?.scheduledDay == past)
            #expect(try await repo.task(id: deleted.id)?.scheduledDay == past)
            #expect(try await repo.task(id: today.id)?.scheduledDay == today.scheduledDay)
            #expect(try await repo.task(id: future.id)?.scheduledDay == future.scheduledDay)
            #expect(try await repo.task(id: fixed.id)?.scheduledDay == fixed.scheduledDay)
            #expect(try await repo.rolloverUnfinishedSingles() == 0)
            var stale = TaskDraft(task: moving); stale.title = "旧草稿"
            await #expect(throws: DomainError.conflict) { try await repo.saveTask(stale) }
        }
    }
    @Test func rolloverCatchesUpAfterOfflineAndMovesAgainOnNextDayUntilCompleted() async throws {
        try await withRepository { repo, url in
            let task = try await repo.saveTask(draft()).task
            try await repo.close()
            let later = ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z")!
            let reopened = try TodoRepository(url: url, now: { later }, timeZone: { TimeZone(secondsFromGMT: 0)! })
            #expect(try await reopened.rolloverUnfinishedSingles() == 1)
            #expect(try await reopened.task(id: task.id)?.scheduledDay == (try d("2026-11-05")))
            #expect(try await reopened.task(id: task.id)?.revision == 2)
            #expect(try await reopened.rolloverUnfinishedSingles() == 0)
            try await reopened.close()
            let next = later.addingTimeInterval(86400)
            let following = try TodoRepository(url: url, now: { next }, timeZone: { TimeZone(secondsFromGMT: 0)! })
            #expect(try await following.rolloverUnfinishedSingles() == 1)
            #expect(try await following.task(id: task.id)?.scheduledDay == (try d("2026-11-06")))
            #expect(try await following.task(id: task.id)?.revision == 3)
            _ = try await following.setCompletion(id: task.id, completed: true)
            try await following.close()
            let afterCompletion = next.addingTimeInterval(86400)
            let completed = try TodoRepository(url: url, now: { afterCompletion }, timeZone: { TimeZone(secondsFromGMT: 0)! })
            #expect(try await completed.rolloverUnfinishedSingles() == 0)
            #expect(try await completed.task(id: task.id)?.scheduledDay == (try d("2026-11-06")))
            try await completed.close()
        }
    }
}
