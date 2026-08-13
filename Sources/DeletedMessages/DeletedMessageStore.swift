import Foundation

/// Shared preference key for the deleted-message feature.
///
/// The key is intentionally kept stable so builds based on the upstream PR
/// can keep their setting when they move to this implementation.
public let kTGExtraShowDeletedMessages = "TGExtraShowDeletedMessages"

public struct DeletedMessageEntry: Codable, Equatable {
    public let messageId: Int32
    public let peerId: Int64
    public let text: String?
    public let authorName: String?
    public let timestamp: Int32
    public let deletedAt: TimeInterval

    public init(
        messageId: Int32,
        peerId: Int64,
        text: String?,
        authorName: String?,
        timestamp: Int32
    ) {
        self.messageId = messageId
        self.peerId = peerId
        self.text = text.map { String($0.prefix(4096)) }
        self.authorName = authorName.map { String($0.prefix(256)) }
        self.timestamp = timestamp
        self.deletedAt = Date().timeIntervalSince1970
    }
}

private struct DeletedMessageKey: Hashable {
    let messageId: Int32
    let peerId: Int64
}

/// Bounded, thread-safe storage for captured messages.
///
/// JSON is decoded once during initialization. The UI hook uses `contains`,
/// which only consults the in-memory index; persistence is performed only
/// after a save, removal, or clear operation.
public final class DeletedMessageStore {
    public static let shared = DeletedMessageStore()

    private static let maximumEntries = 500
    private static let storageKey = "tgextra_deleted_entries"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cachedEntries: [DeletedMessageEntry]
    private var entryKeys: Set<DeletedMessageKey>

    private init() {
        let suite = UserDefaults(suiteName: "com.tgextra.deletedMessages")
        self.defaults = suite ?? .standard

        let loadedEntries: [DeletedMessageEntry]
        if let data = self.defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([DeletedMessageEntry].self, from: data) {
            var seen = Set<DeletedMessageKey>()
            let uniqueEntries = decoded.filter { entry in
                guard entry.messageId != 0, entry.peerId != 0 else { return false }
                return seen.insert(
                    DeletedMessageKey(messageId: entry.messageId, peerId: entry.peerId)
                ).inserted
            }
            loadedEntries = Array(uniqueEntries.suffix(Self.maximumEntries))
        } else {
            loadedEntries = []
        }

        self.cachedEntries = loadedEntries
        self.entryKeys = Set(loadedEntries.map {
            DeletedMessageKey(messageId: $0.messageId, peerId: $0.peerId)
        })
    }

    public func contains(messageId: Int32, peerId: Int64) -> Bool {
        guard messageId != 0, peerId != 0 else { return false }

        lock.lock()
        defer { lock.unlock() }
        return entryKeys.contains(DeletedMessageKey(messageId: messageId, peerId: peerId))
    }

    public func allEntries() -> [DeletedMessageEntry] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries
    }

    public func entries(forPeerId peerId: Int64) -> [DeletedMessageEntry] {
        guard peerId != 0 else { return [] }

        lock.lock()
        defer { lock.unlock() }
        return cachedEntries.filter { $0.peerId == peerId }
    }

    public func save(_ entry: DeletedMessageEntry) {
        guard entry.messageId != 0, entry.peerId != 0 else { return }

        let key = DeletedMessageKey(messageId: entry.messageId, peerId: entry.peerId)
        lock.lock()
        if entryKeys.contains(key) {
            lock.unlock()
            return
        }

        cachedEntries.append(entry)
        if cachedEntries.count > Self.maximumEntries {
            cachedEntries = Array(cachedEntries.suffix(Self.maximumEntries))
        }
        entryKeys = Set(cachedEntries.map {
            DeletedMessageKey(messageId: $0.messageId, peerId: $0.peerId)
        })
        // This is an infrequent delete event, never a cell/layout operation.
        persist(cachedEntries)
        lock.unlock()
    }

    public func remove(messageId: Int32, peerId: Int64) {
        guard messageId != 0, peerId != 0 else { return }

        let key = DeletedMessageKey(messageId: messageId, peerId: peerId)

        lock.lock()
        guard entryKeys.contains(key) else {
            lock.unlock()
            return
        }
        cachedEntries.removeAll { $0.messageId == messageId && $0.peerId == peerId }
        entryKeys.remove(key)
        persist(cachedEntries)
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        cachedEntries.removeAll(keepingCapacity: false)
        entryKeys.removeAll(keepingCapacity: false)
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }

    private func persist(_ entries: [DeletedMessageEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
