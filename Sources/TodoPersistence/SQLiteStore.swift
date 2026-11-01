import CoreData
import TodoDomain

/// All managed objects and coordinator operations are confined to `context`'s
/// private queue. Public inputs/outputs are Sendable value snapshots only.
public final class SQLiteStore: @unchecked Sendable {
    private let coordinator: NSPersistentStoreCoordinator
    private let context: NSManagedObjectContext

    public init(url: URL, readOnly: Bool = false) throws {
        let fresh = !FileManager.default.fileExists(atPath: url.path)
        if !readOnly { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: StoreSchema.makeModel())
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: [
            NSReadOnlyPersistentStoreOption: readOnly,
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ])
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
        context.undoManager = nil
        if fresh && !readOnly { try replace(with: StoreSnapshot()) }
        // Corrupt/incompatible existing stores are never silently replaced by empty data.
        try ModelValidator.snapshot(configuration())
    }

    public func snapshot() throws -> StoreSnapshot {
        try context.performAndWait {
            var result = StoreSnapshot()
            result.categories = try read(.category)
            result.tasks = try read(.task)
            result.series = try read(.series)
            result.rules = try read(.rule)
            result.exclusions = try read(.exclusion)
            result.countdowns = try read(.countdown)
            return result
        }
    }

    public func configuration() throws -> StoreSnapshot {
        try context.performAndWait {
            var result = StoreSnapshot()
            result.categories = try read(.category)
            result.series = try read(.series)
            result.rules = try read(.rule)
            result.exclusions = try read(.exclusion)
            return result
        }
    }

    public func task(id: UUID) throws -> TodoItem? {
        try context.performAndWait {
            let values: [TodoItem] = try read(.task, predicate: NSPredicate(format: "id == %@", id as NSUUID))
            return values.first
        }
    }

    /// Used for complete snapshot restoration, not for interactive typing.
    /// No batch delete: one context save is the atomic commit point.
    public func replace(with snapshot: StoreSnapshot) throws {
        try ModelValidator.snapshot(snapshot)
        try context.performAndWait {
            do {
                try sync(snapshot.categories, kind: .category)
                try sync(snapshot.series, kind: .series)
                try sync(snapshot.rules, kind: .rule)
                try sync(snapshot.tasks, kind: .task)
                try sync(snapshot.exclusions, kind: .exclusion)
                try sync(snapshot.countdowns, kind: .countdown)
                if context.hasChanges { try context.save() }
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func agendaInput(in interval: DayInterval) throws -> StoreSnapshot {
        try context.performAndWait {
            var result = StoreSnapshot()
            result.categories = try read(.category)
            result.series = try read(.series)
            result.rules = try read(.rule)
            result.exclusions = try read(.exclusion)
            let predicate = NSPredicate(format: "(scheduledDay >= %@ AND scheduledDay < %@) OR (occurrenceDay >= %@ AND occurrenceDay < %@)",
                                        interval.start.description, interval.endExclusive.description,
                                        interval.start.description, interval.endExclusive.description)
            // The year 10000 sentinel is not lexically ordered as a four-digit year.
            if interval.endExclusive.year == 10000 {
                result.tasks = try read(.task, predicate: NSPredicate(format: "scheduledDay >= %@ OR occurrenceDay >= %@", interval.start.description, interval.start.description))
            } else {
                result.tasks = try read(.task, predicate: predicate)
            }
            return result
        }
    }

    public func close() throws {
        try context.performAndWait {
            context.reset()
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
    }

    func records<T: Decodable & Sendable>(_ kind: StoreEntity, matching format: String? = nil,
                                         values: [StoreQueryValue] = [], order: [StoreSort] = [], limit: Int = 0) throws -> [T] {
        try context.performAndWait {
            let predicate = format.map { NSPredicate(format: $0, argumentArray: values.map(\.foundationValue)) }
            let sort = order.isEmpty ? nil : order.map { NSSortDescriptor(key: $0.key, ascending: $0.ascending) }
            return try read(kind, predicate: predicate, sort: sort, limit: limit)
        }
    }

    private func read<T: Decodable & Sendable>(_ kind: StoreEntity, predicate: NSPredicate? = nil,
                                    sort: [NSSortDescriptor]? = nil, limit: Int = 0) throws -> [T] {
        let request = NSFetchRequest<NSManagedObject>(entityName: kind.rawValue)
        request.predicate = predicate
        request.fetchBatchSize = 100
        request.sortDescriptors = sort ?? [NSSortDescriptor(key: "id", ascending: true)]
        request.fetchLimit = limit
        return try context.fetch(request).map { object in
            var record: [String: Any] = [:]
            for (name, attribute) in object.entity.attributesByName {
                guard let value = object.value(forKey: name) else { continue }
                if name == "weekdays", let mask = value as? NSNumber {
                    record[name] = (1...7).filter { mask.intValue & (1 << ($0 - 1)) != 0 }
                } else if attribute.attributeType == .UUIDAttributeType, let id = value as? UUID {
                    record[name] = id.uuidString
                } else if attribute.attributeType == .dateAttributeType, let date = value as? Date {
                    record[name] = date.timeIntervalSinceReferenceDate
                } else if attribute.attributeType == .booleanAttributeType, let number = value as? NSNumber {
                    record[name] = number.boolValue
                } else { record[name] = value }
            }
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: record))
        }
    }

    private func sync<T: Encodable & Identifiable>(_ values: [T], kind: StoreEntity) throws where T.ID == UUID {
        let request = NSFetchRequest<NSManagedObject>(entityName: kind.rawValue)
        let existing = try context.fetch(request)
        let byID = Dictionary(uniqueKeysWithValues: existing.compactMap { object in
            (object.value(forKey: "id") as? UUID).map { ($0, object) }
        })
        let retained = Set(values.map(\.id))
        for object in existing where !(object.value(forKey: "id").flatMap { $0 as? UUID }.map(retained.contains) ?? false) { context.delete(object) }
        for value in values {
            let object = byID[value.id] ?? NSEntityDescription.insertNewObject(forEntityName: kind.rawValue, into: context)
            try assign(value, to: object)
        }
    }

    private func assign<T: Encodable>(_ value: T, to object: NSManagedObject) throws {
        var record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        if let category = value as? TodoCategory { record["normalizedName"] = category.normalizedName }
        if let task = value as? TodoItem { record["occurrenceKey"] = task.occurrenceKey }
        if let exclusion = value as? TodoOccurrenceExclusion { record["occurrenceKey"] = exclusion.occurrenceKey }
        for (name, attribute) in object.entity.attributesByName {
            guard let raw = record[name], !(raw is NSNull) else { object.setValue(nil, forKey: name); continue }
            let mapped: Any
            if name == "weekdays", let days = raw as? [Int] {
                mapped = days.reduce(0) { $0 | (1 << ($1 - 1)) }
            } else if attribute.attributeType == .UUIDAttributeType, let text = raw as? String {
                mapped = UUID(uuidString: text)! as NSUUID
            } else if attribute.attributeType == .dateAttributeType, let seconds = raw as? Double {
                mapped = Date(timeIntervalSinceReferenceDate: seconds)
            } else { mapped = raw }
            if let old = object.value(forKey: name) as? NSObject, let new = mapped as? NSObject, old.isEqual(new) { continue }
            object.setValue(mapped, forKey: name)
        }
    }
}

enum StoreQueryValue: Sendable {
    case text(String), date(Date), uuid(UUID)
    var foundationValue: Any {
        switch self { case .text(let v): v; case .date(let v): v as NSDate; case .uuid(let v): v as NSUUID }
    }
}
struct StoreSort: Sendable {
    var key: String
    var ascending: Bool
    init(_ key: String, ascending: Bool) { self.key = key; self.ascending = ascending }
}

struct RevisionExpectation: Sendable {
    var entity: StoreEntity
    var id: UUID
    /// Zero means the ID must be absent; otherwise it must match this revision.
    var revision: Int64
}

struct StoreChanges: Sendable {
    var categories: [TodoCategory] = []
    var tasks: [TodoItem] = []
    var series: [TodoSeries] = []
    var rules: [TodoSeriesRule] = []
    var exclusions: [TodoOccurrenceExclusion] = []
    var countdowns: [CountdownEvent] = []
    var removals: [StoreEntity: Set<UUID>] = [:]
    var expectations: [RevisionExpectation] = []
}

extension SQLiteStore {
    /// Incremental command commit. Only supplied IDs are touched; unrelated rows
    /// are neither decoded nor rewritten. Cross-record validity is checked before save.
    func commit(_ changes: StoreChanges) throws {
        try context.performAndWait {
            do {
                for (kind, expectations) in Dictionary(grouping: changes.expectations, by: \.entity) {
                    let records = try recordsByID(kind, ids: Set(expectations.map(\.id)))
                    for expected in expectations {
                        let record = records[expected.id]
                        let revision = (record?.value(forKey: "revision") as? NSNumber)?.int64Value ?? 0
                        guard revision == expected.revision, (expected.revision == 0) == (record == nil) else { throw DomainError.conflict }
                    }
                }
                var config = try configuration()
                func merged<T: Identifiable>(_ before: [T], _ after: [T], _ kind: StoreEntity) -> [T] where T.ID == UUID {
                    let replaced = Set(after.map(\.id)).union(changes.removals[kind] ?? [])
                    return before.filter { !replaced.contains($0.id) } + after
                }
                config.categories = merged(config.categories, changes.categories, .category)
                config.series = merged(config.series, changes.series, .series)
                config.rules = merged(config.rules, changes.rules, .rule)
                config.exclusions = merged(config.exclusions, changes.exclusions, .exclusion)
                config.tasks = changes.tasks
                config.countdowns = changes.countdowns
                try ModelValidator.snapshot(config)

                for (kind, ids) in changes.removals where !ids.isEmpty {
                    let request = NSFetchRequest<NSManagedObject>(entityName: kind.rawValue)
                    request.predicate = NSPredicate(format: "id IN %@", ids.map { $0 as NSUUID })
                    for object in try context.fetch(request) { context.delete(object) }
                }
                try upsert(changes.categories, kind: .category)
                try upsert(changes.series, kind: .series)
                try upsert(changes.rules, kind: .rule)
                try upsert(changes.tasks, kind: .task)
                try upsert(changes.exclusions, kind: .exclusion)
                try upsert(changes.countdowns, kind: .countdown)

                func requireReferences(_ kind: StoreEntity, _ property: String, _ ids: [UUID]) throws {
                    let request = NSFetchRequest<NSManagedObject>(entityName: kind.rawValue)
                    request.predicate = ids.isEmpty
                        ? NSPredicate(format: "%K != nil", property)
                        : NSPredicate(format: "%K != nil AND NOT (%K IN %@)", property, property, ids.map { $0 as NSUUID })
                    guard try context.fetch(request).isEmpty else { throw DomainError.invalidSnapshot("\(kind.rawValue) 的 \(property) 关联失效") }
                }
                try requireReferences(.task, "categoryID", config.categories.map(\.id))
                try requireReferences(.task, "seriesID", config.series.map(\.id))
                try requireReferences(.task, "ruleVersionID", config.rules.map(\.id))
                if context.hasChanges { try context.save() }
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func upsert<T: Encodable & Identifiable>(_ values: [T], kind: StoreEntity) throws where T.ID == UUID {
        let existing = try recordsByID(kind, ids: Set(values.map(\.id)))
        for value in values {
            let object = existing[value.id] ?? NSEntityDescription.insertNewObject(forEntityName: kind.rawValue, into: context)
            try assign(value, to: object)
        }
    }
    /// Chunked IN queries avoid a round trip for each generated occurrence while
    /// keeping the bind list bounded for large rollovers/type migrations.
    private func recordsByID(_ kind: StoreEntity, ids: Set<UUID>) throws -> [UUID: NSManagedObject] {
        let ids = Array(ids)
        var result: [UUID: NSManagedObject] = [:]
        for start in stride(from: 0, to: ids.count, by: 512) {
            let request = NSFetchRequest<NSManagedObject>(entityName: kind.rawValue)
            request.predicate = NSPredicate(format: "id IN %@", ids[start..<min(start + 512, ids.count)].map { $0 as NSUUID })
            for record in try context.fetch(request) {
                if let id = record.value(forKey: "id") as? UUID { result[id] = record }
            }
        }
        return result
    }
}
