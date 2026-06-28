// GlobalSelectionCache.swift
// MarkdownExtendedView

import SwiftUI

public struct MarkdownBlockMappingsAttribute: TextAttribute, Equatable, Hashable {
    public typealias Value = MarkdownBlockMappingsAttribute
    public static let name = "MarkdownBlockMappingsAttribute"
    
    public let mappings: [GlobalSelectionCache.CharacterMapping]
    public init(mappings: [GlobalSelectionCache.CharacterMapping]) {
        self.mappings = mappings
    }
}


import Observation

@Observable
public class GlobalSelectionCache {
    
//    @MainActor static let share = GlobalSelectionCache()
    
    public struct CharacterBounds: Equatable, Sendable {
        public let index: Int
        public let char: String
        public let rect: CGRect // In LOCAL coordinates of the Text view
    }
    
    public struct CharacterMapping: Equatable, Hashable, Sendable {
        public let index: Int
        public let char: String
        public init(index: Int, char: String) {
            self.index = index
            self.char = char
        }
    }
    
    @ObservationIgnored public var runs: [UUID: [CharacterBounds]] = [:]
    
    @ObservationIgnored var resolvedLayouts: [ResolvedLayout] = []
    
    @ObservationIgnored var globalCharacters: [GlobalCharacter] = []
    
    public init() {}
}

//public struct GlobalSelectionCacheEnvironmentKey: EnvironmentKey {
//    public static let defaultValue: GlobalSelectionCache = GlobalSelectionCache()
//}
//
//public extension EnvironmentValues {
//    var globalSelectionCache: GlobalSelectionCache {
//        get { self[GlobalSelectionCacheEnvironmentKey.self] }
//        set { self[GlobalSelectionCacheEnvironmentKey.self] = newValue }
//    }
//}

@MainActor
public struct SelectionLayoutTextRenderer: @MainActor TextRenderer {
    let cache: GlobalSelectionCache
    let blockId: UUID
    
    public func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var extractedBounds: [GlobalSelectionCache.CharacterBounds] = []
        var sliceIndex = 0
        
        for line in layout {
            for run in line {
                if let mappingsAttr = run[MarkdownBlockMappingsAttribute.self] {
                    for slice in run {
                        if sliceIndex < mappingsAttr.mappings.count {
                            let mapping = mappingsAttr.mappings[sliceIndex]
                            extractedBounds.append(.init(index: mapping.index, char: mapping.char, rect: slice.typographicBounds.rect))
                        }
                        sliceIndex += 1
                    }
                }
            }
        }
        
        let current = cache.runs[blockId] ?? []
        if current != extractedBounds {
            cache.runs[blockId] = extractedBounds
        }
        
        // Draw normally
        for line in layout {
            context.draw(line)
        }
    }
}
