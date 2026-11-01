import Foundation
import TodoDomain

/// A small atomic manifest selects the active database. Recovery creates a new
/// sibling store and never renames, removes, or overwrites the failed one.
public enum StoreLocation {
    private struct Manifest: Codable { let version: Int; let filename: String }
    public static func resolve(in directory: URL) throws -> URL {
        let marker = directory.appendingPathComponent("StoreLocation.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return directory.appendingPathComponent("TodoDesktop.sqlite") }
        let metadata = try marker.resourceValues(forKeys: [.fileSizeKey])
        guard (metadata.fileSize ?? Int.max) <= 4096 else { throw DomainError.invalidSnapshot("本机存储位置配置过大") }
        let value = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: marker))
        guard value.version == 1, validFilename(value.filename) else { throw DomainError.invalidSnapshot("本机存储位置配置无效，原数据未更改") }
        let active = directory.appendingPathComponent(value.filename)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: active.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw DomainError.invalidSnapshot("活动数据库文件缺失，原数据目录已保留，请选择恢复或重新尝试")
        }
        return active
    }
    static func activate(_ url: URL) throws {
        guard validFilename(url.lastPathComponent) else { throw DomainError.invalidSnapshot("恢复库文件名无效") }
        let directory = url.deletingLastPathComponent(), marker = directory.appendingPathComponent("StoreLocation.json")
        if FileManager.default.fileExists(atPath: marker.path) {
            // Preserve even a damaged old manifest before replacing it.
            let backup = directory.appendingPathComponent("StoreLocation-before-recovery-\(UUID()).json")
            try FileManager.default.copyItem(at: marker, to: backup)
        }
        let data = try JSONEncoder().encode(Manifest(version: 1, filename: url.lastPathComponent))
        try data.write(to: marker, options: .atomic)
    }
    private static func validFilename(_ name: String) -> Bool {
        if name == "TodoDesktop.sqlite" { return true }
        guard name.hasPrefix("Recovered-"), name.hasSuffix(".sqlite") else { return false }
        return UUID(uuidString: String(name.dropFirst(10).dropLast(7))) != nil
    }
}

public struct RecoveredStore: Sendable {
    public let url: URL
    public let repository: TodoRepository
}

public enum StoreRecovery {
    public static func create(from data: Data, in directory: URL, clock: AppClock = .system) async throws -> RecoveredStore {
        // Reject bad input before creating any new files or changing the marker.
        _ = try SnapshotCodec.decode(data)
        let url = directory.appendingPathComponent("Recovered-\(UUID()).sqlite")
        var candidate: TodoRepository?
        do {
            let repository = try TodoRepository(url: url, now: clock.now, timeZone: clock.timeZone)
            candidate = repository
            try await repository.restoreData(data)
            try StoreLocation.activate(url)
            return RecoveredStore(url: url, repository: repository)
        } catch {
            try? await candidate?.close()
            // Only this invocation's unique, unpublished candidate is removed.
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
            throw error
        }
    }
}
