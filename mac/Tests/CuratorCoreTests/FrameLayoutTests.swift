import Foundation
import Testing
@testable import CuratorCore

/// Frames of a moment are laid out so that all of them are visible at once, as large as possible.
@Test func fourFramesShareOneRow() {
    let l = frameLayout(count: 4, ratio: 1.5, width: 1000, height: 650, below: 170)
    #expect(l.columns == 4 && l.fits)
    #expect(abs(l.frameWidth - 238) < 1)
}

@Test func eightFramesWrapIntoTwoRows() {
    let l = frameLayout(count: 8, ratio: 1.5, width: 1000, height: 650, below: 170)
    #expect(l.columns == 4 && l.rows == 2 && l.fits)
    #expect(l.frameWidth >= 200)
}

@Test func oneFrameIsLimitedByTheHeight() {
    let l = frameLayout(count: 1, ratio: 1.5, width: 1400, height: 600, below: 170)
    #expect(l.columns == 1 && l.fits)
    #expect(abs(l.frameWidth - 645) < 1)            // (600 − 170) × 1.5
}

@Test func tooManyFramesScrollDownNeverSideways() {
    let l = frameLayout(count: 30, ratio: 1.5, width: 1000, height: 650, below: 170)
    #expect(!l.fits)
    #expect(l.columns >= 4)
    #expect(CGFloat(l.columns) * l.frameWidth + CGFloat(l.columns - 1) * 16 <= 1000.5)   // never wider than the space
}
