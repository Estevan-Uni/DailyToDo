import CoreData

enum StoreEntity: String, CaseIterable, Sendable {
    case category = "TodoCategory", task = "TodoItem", series = "TodoSeries"
    case rule = "TodoSeriesRule", exclusion = "TodoOccurrenceExclusion", countdown = "CountdownEvent"
}

enum StoreSchema {
    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let value = NSAttributeDescription()
        value.name = name; value.attributeType = type; value.isOptional = optional
        return value
    }
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["TodoDesktopV1"]
        var entities: [NSEntityDescription] = []
        for kind in StoreEntity.allCases {
            let entity = NSEntityDescription()
            entity.name = kind.rawValue
            entity.managedObjectClassName = "NSManagedObject"
            var properties = [attribute("id", .UUIDAttributeType)]
            func add(_ names: [String], _ type: NSAttributeType, optional: Bool = false) {
                properties += names.map { attribute($0, type, optional: optional) }
            }
            switch kind {
            case .category:
                add(["name", "normalizedName", "colorHex"], .stringAttributeType)
                add(["sortOrder", "revision"], .integer64AttributeType)
                add(["isSystemDefault"], .booleanAttributeType)
                add(["createdAt", "updatedAt"], .dateAttributeType)
            case .task:
                add(["title", "notes", "scheduledDay", "occurrenceKey"], .stringAttributeType)
                add(["occurrenceDay"], .stringAttributeType, optional: true)
                add(["scheduledMinute", "revision"], .integer64AttributeType)
                add(["categoryID"], .UUIDAttributeType)
                add(["seriesID", "ruleVersionID"], .UUIDAttributeType, optional: true)
                add(["isImportant", "isOverride", "isRuleSuppressed"], .booleanAttributeType)
                add(["createdAt", "updatedAt"], .dateAttributeType)
                add(["completedAt", "reminderAt", "deletedAt"], .dateAttributeType, optional: true)
            case .series:
                add(["stoppedFromDay"], .stringAttributeType, optional: true)
                add(["revision"], .integer64AttributeType)
                add(["createdAt", "updatedAt"], .dateAttributeType)
            case .rule:
                add(["seriesID", "categoryID"], .UUIDAttributeType)
                add(["effectiveFromDay", "title", "notes", "frequency"], .stringAttributeType)
                add(["endDay"], .stringAttributeType, optional: true)
                add(["minute", "weekdays"], .integer64AttributeType)
                add(["reminderOffsetMinutes"], .integer64AttributeType, optional: true)
                add(["isSupersededForExpansion"], .booleanAttributeType)
                add(["isImportant"], .booleanAttributeType)
            case .exclusion:
                add(["seriesID"], .UUIDAttributeType)
                add(["day", "reason", "occurrenceKey"], .stringAttributeType)
                add(["createdAt"], .dateAttributeType)
            case .countdown:
                add(["title", "notes", "targetDay"], .stringAttributeType)
                add(["revision"], .integer64AttributeType)
                add(["createdAt", "updatedAt"], .dateAttributeType)
                add(["archivedAt", "reminderAt", "deletedAt"], .dateAttributeType, optional: true)
            }
            entity.properties = properties
            entity.uniquenessConstraints = [["id"]]
            if kind == .category { entity.uniquenessConstraints.append(["normalizedName"]) }
            if kind == .task || kind == .exclusion { entity.uniquenessConstraints.append(["occurrenceKey"]) }
            let indexed: [String]
            switch kind {
            case .task: indexed = ["scheduledDay", "occurrenceDay", "seriesID", "completedAt", "deletedAt"]
            case .rule: indexed = ["seriesID", "effectiveFromDay"]
            case .countdown: indexed = ["targetDay", "deletedAt"]
            case .exclusion: indexed = ["seriesID", "day"]
            default: indexed = []
            }
            entity.indexes = indexed.map { name in
                NSFetchIndexDescription(name: "\(kind.rawValue)_\(name)", elements: [NSFetchIndexElementDescription(property: properties.first { $0.name == name }!, collationType: .binary)])
            }
            entities.append(entity)
        }
        model.entities = entities
        return model
    }
}
