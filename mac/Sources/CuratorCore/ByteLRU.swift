import Foundation

// M13: the thumbnail cache is bounded by bytes, not by count: 3,000 thumbnails at 520 px would be 3 GB of
// bitmaps. A least-recently-used list with O(1) get, insert and evict. Pure, so it is unit-tested; the app's
// ThumbnailCache (main actor) holds one.

public struct ByteLRU<Key: Hashable, Value> {
    private struct Node {
        var value: Value
        var cost: Int
        var newer: Key?
        var older: Key?
    }

    public let limit: Int
    public private(set) var totalCost = 0
    private var nodes: [Key: Node] = [:]
    private var newest: Key?
    private var oldest: Key?

    /// `limit`: the most bytes kept. One item larger than the limit is still kept (alone), so a large photo can
    /// always be shown.
    public init(limit: Int) { self.limit = max(0, limit) }

    public var count: Int { nodes.count }

    /// The value, marked as just used.
    public mutating func value(for key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        moveToNewest(key)
        return node.value
    }

    /// The value without changing the order.
    public func peek(_ key: Key) -> Value? { nodes[key]?.value }

    public func contains(_ key: Key) -> Bool { nodes[key] != nil }

    /// Stores a value as the newest and evicts the oldest until the total fits. Returns the evicted keys.
    @discardableResult
    public mutating func insert(_ value: Value, for key: Key, cost: Int) -> [Key] {
        if nodes[key] != nil { remove(key) }
        let c = max(0, cost)
        nodes[key] = Node(value: value, cost: c, newer: nil, older: newest)
        if let n = newest { nodes[n]?.newer = key }
        newest = key
        if oldest == nil { oldest = key }
        totalCost += c
        var evicted: [Key] = []
        while totalCost > limit, let o = oldest, o != key {
            remove(o)
            evicted.append(o)
        }
        return evicted
    }

    @discardableResult
    public mutating func remove(_ key: Key) -> Value? {
        guard let node = nodes.removeValue(forKey: key) else { return nil }
        if let n = node.newer { nodes[n]?.older = node.older } else { newest = node.older }
        if let o = node.older { nodes[o]?.newer = node.newer } else { oldest = node.newer }
        totalCost -= node.cost
        return node.value
    }

    public mutating func removeAll() {
        nodes = [:]
        newest = nil
        oldest = nil
        totalCost = 0
    }

    /// Keys from the most to the least recently used (tests and diagnostics).
    public var keysByRecency: [Key] {
        var out: [Key] = []
        var k = newest
        while let key = k {
            out.append(key)
            k = nodes[key]?.older
        }
        return out
    }

    private mutating func moveToNewest(_ key: Key) {
        guard newest != key, let node = nodes[key] else { return }
        // unlink
        if let n = node.newer { nodes[n]?.older = node.older }
        if let o = node.older { nodes[o]?.newer = node.newer } else { oldest = node.newer }
        // link as newest
        nodes[key]?.older = newest
        nodes[key]?.newer = nil
        if let n = newest { nodes[n]?.newer = key }
        newest = key
    }
}

// MARK: thumbnail sizes

/// Thumbnail sizes (points) the cache makes: few sizes, many hits. Grid and stage cells up to 150 pt use 160.
public let thumbnailBuckets = [160, 260, 520, 1024, 2048]

/// The smallest bucket that covers `side` points (the largest bucket above that).
public func thumbnailBucket(_ side: Double) -> Int {
    thumbnailBuckets.first { Double($0) >= side } ?? thumbnailBuckets[thumbnailBuckets.count - 1]
}

/// Bytes of a decoded RGBA bitmap.
public func thumbnailCost(pixelWidth: Int, pixelHeight: Int) -> Int { max(0, pixelWidth) * max(0, pixelHeight) * 4 }

/// Bitmap memory the thumbnail cache may hold (M13 budget: the whole app under 1 GB with 3,000 photos).
public let thumbnailCacheBudgetBytes = 384 * 1024 * 1024
