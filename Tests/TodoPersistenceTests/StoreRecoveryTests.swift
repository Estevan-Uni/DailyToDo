import Foundation
import Testing
import TodoDomain
@testable import TodoPersistence

@Suite struct StoreRecoveryTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TodoRecoveryTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func recoveryPublishesNewStoreAndPreservesFailedBytes() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("TodoDesktop.sqlite"), damaged = Data("deliberately damaged test store".utf8)
        try damaged.write(to: original)
        var snapshot = StoreSnapshot()
        let task = TodoItem(title: "恢复验证", scheduledDay: try LocalDate("2030-01-10"), scheduledMinute: 540, categoryID: snapshot.categories[0].id)
        snapshot.tasks = [task]
        let recovered = try await StoreRecovery.create(from: SnapshotCodec.encode(snapshot), in: directory)
        #expect(recovered.url != original)
        #expect(try Data(contentsOf: original) == damaged)
        #expect(try StoreLocation.resolve(in: directory) == recovered.url)
        #expect(try await recovered.repository.task(id: task.id) == task)
        try await recovered.repository.close()
        let reopened = try TodoRepository(url: StoreLocation.resolve(in: directory))
        #expect(try await reopened.task(id: task.id) == task)
        try await reopened.close()
    }
    @Test func malformedBackupDoesNotCreateStoreOrChangeManifest() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("StoreLocation.json"), original = Data("broken marker".utf8)
        try original.write(to: marker)
        await #expect(throws: (any Error).self) { try await StoreRecovery.create(from: Data("invalid".utf8), in: directory) }
        #expect(try Data(contentsOf: marker) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["StoreLocation.json"])
    }
    @Test func recoveredRepositoryKeepsTheInjectedCivilClockForRollover() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-31T23:30:00Z"))
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let clock = AppClock(now: { instant }, timeZone: { zone })
        var snapshot = StoreSnapshot()
        let task = TodoItem(title: "恢复后顺延", scheduledDay: try LocalDate("2026-12-31"), scheduledMinute: 540, categoryID: snapshot.categories[0].id)
        snapshot.tasks = [task]
        let recovered = try await StoreRecovery.create(from: SnapshotCodec.encode(snapshot), in: directory, clock: clock)
        #expect(try await recovered.repository.rolloverUnfinishedSingles() == 1)
        let moved = try #require(await recovered.repository.task(id: task.id))
        #expect(moved.scheduledDay == (try LocalDate("2027-01-01")) && moved.scheduledMinute == 540)
        #expect(moved.updatedAt == instant && moved.id == task.id)
        try await recovered.repository.close()
    }
    @Test func manifestRejectsTraversalAndUnknownVersions() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("StoreLocation.json")
        for value in [#"{"version":1,"filename":"../TodoDesktop.sqlite"}"#, #"{"version":99,"filename":"TodoDesktop.sqlite"}"#] {
            try Data(value.utf8).write(to: marker)
            #expect(throws: (any Error).self) { try StoreLocation.resolve(in: directory) }
        }
    }
    @Test func recoveryPreservesDamagedManifestBeforeReplacingIt() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("StoreLocation.json"), original = Data("invalid old metadata".utf8)
        try original.write(to: marker)
        let recovered = try await StoreRecovery.create(from: SnapshotCodec.encode(StoreSnapshot()), in: directory)
        let backup = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("StoreLocation-before-recovery-") })
        #expect(try Data(contentsOf: backup) == original)
        #expect(try StoreLocation.resolve(in: directory) == recovered.url)
        try await recovered.repository.close()
    }
    @Test func missingActiveStoreDoesNotCreateEmptyDatabaseOrFallBack() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("TodoDesktop.sqlite")
        let originalBytes = Data("preserved original database fixture".utf8)
        try originalBytes.write(to: original)
        let filename = "Recovered-\(UUID()).sqlite"
        let marker = directory.appendingPathComponent("StoreLocation.json")
        let manifest = Data("{\"version\":1,\"filename\":\"\(filename)\"}".utf8)
        try manifest.write(to: marker)
        #expect(throws: (any Error).self) { try StoreLocation.resolve(in: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path))
        #expect(try Data(contentsOf: original) == originalBytes)
        #expect(try Data(contentsOf: marker) == manifest)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(filename), withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try StoreLocation.resolve(in: directory) }
    }
}
