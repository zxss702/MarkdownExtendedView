// GlobalSelectionCache.swift
// MarkdownExtendedView

import SwiftUI

// MarkdownCharacterAttribute: Only needs TextAttribute conformance.
// Set via Text.customAttribute(), read via run[MarkdownCharacterAttribute.self] in TextRenderer.
@available(macOS 15.0, iOS 18.0, *)
public struct MarkdownCharacterAttribute: TextAttribute, Equatable, Hashable {
    public let index: Int
    public let char: String
    public init(index: Int, char: String) {
        self.index = index
        self.char = char
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
    
    @ObservationIgnored public var runs: [UUID: [CharacterBounds]] = [:]
    
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
        
        for line in layout {
            for run in line {
                if let charData = run[MarkdownCharacterAttribute.self] {
                    extractedBounds.append(.init(index: charData.index, char: charData.char, rect: run.typographicBounds.rect))
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
