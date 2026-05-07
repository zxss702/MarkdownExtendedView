import XCTest
import SwiftUI
@testable import MarkdownExtendedView

final class MathBenchmarkTests: XCTestCase {
    
    /// Test the performance of parsing and typesetting a complex formula (Cache Miss).
    func testFormulaMeasurePerformance() {
        let formula = "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"
        let cache = MathDisplayCache.shared
        
        self.measure {
            // By constantly changing the font size, we force a cache miss and trigger full AST parsing + layout
            for i in 0..<100 {
                _ = cache.getDisplay(latex: formula, fontSize: CGFloat(16 + i), isBlock: true)
            }
        }
    }
    
    /// Test the performance of fetching an already calculated formula (Cache Hit).
    func testFormulaMeasureCachedPerformance() {
        let formula = "\\int_{a}^{b} x^2 dx"
        let cache = MathDisplayCache.shared
        
        // Pre-warm the cache
        _ = cache.getDisplay(latex: formula, fontSize: 16.0, isBlock: true)
        
        self.measure {
            // Fetching the same formula 10,000 times
            for _ in 0..<10_000 {
                _ = cache.getDisplay(latex: formula, fontSize: 16.0, isBlock: true)
            }
        }
    }
}
