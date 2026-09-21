// MarkdownRenderSnapshot.swift
//  MarkdownExtendedView
//
//  Synchronous snapshot cache. `getOrBuild` is a pure main-thread
//  function: on a cache hit it returns the stored `[MDBlock]` in O(1);
//  on a miss it parses + flattens the content immediately. No async
//  work is ever scheduled from this file.

import Foundation
@preconcurrency import Markdown

@MainActor
enum MarkdownSnapshotCache {

    /// Returns the flattened block model for `content`, building it
    /// synchronously on a cache miss. Ids are reused from the most
    /// recently built snapshot so streaming updates keep view identity.
    /// `baseURL` participates in the cache key because link destinations
    /// are resolved during flattening.
    static func getOrBuild(_ content: String, baseURL: URL?) -> [MDBlock] {
        let key = "\(baseURL?.absoluteString ?? "")\u{0}\(content)" as NSString
        if let cached = cache.object(forKey: key) {
            latest = cached.blocks
            return cached.blocks
        }
        let blocks = MarkdownFlattener.flatten(content, baseURL: baseURL, previousBlocks: latest ?? [])
        cache.setObject(MDBlocksBox(blocks: blocks), forKey: key)
        latest = blocks
        return blocks
    }

    /// Clears cached snapshots (used by tests).
    static func reset() {
        cache.removeAllObjects()
        latest = nil
    }

    // MARK: - Private

    private static let cache: NSCache<NSString, MDBlocksBox> = {
        let cache = NSCache<NSString, MDBlocksBox>()
        cache.countLimit = 128
        return cache
    }()

    /// The most recently built block array, used as the `previousBlocks`
    /// source for id reuse on the next (streaming) build.
    private static var latest: [MDBlock]?
}

private final class MDBlocksBox: NSObject {
    let blocks: [MDBlock]

    init(blocks: [MDBlock]) {
        self.blocks = blocks
    }
}
