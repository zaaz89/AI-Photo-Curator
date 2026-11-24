import Testing
@testable import CuratorCore

@Test func spacingScaleIsStrictlyIncreasing() {
    let s = SpaceScale.all
    #expect(s.count == 10)
    #expect(zip(s, s.dropFirst()).allSatisfy { $0 < $1 })
    #expect(s.allSatisfy { $0 > 0 && $0.rounded() == $0 })
}

@Test func radiusScaleIsStrictlyIncreasing() {
    let r = RadiusScale.all
    #expect(zip(r, r.dropFirst()).allSatisfy { $0 < $1 })
}

@Test func springsMatchTheSpec() {
    #expect(MotionToken.arrive.curve == .spring(response: 0.45, dampingFraction: 0.82))
    #expect(MotionToken.settle.curve == .spring(response: 0.6, dampingFraction: 0.9))
    #expect(MotionToken.drop.curve == .spring(response: 0.35, dampingFraction: 0.7))
    #expect(MotionToken.stack.curve == .spring(response: 0.5, dampingFraction: 0.85))
    #expect(MotionToken.quick.curve.isSpring)
}

@Test func reducedMotionIsNeverASpring() {
    for token in MotionToken.allCases {
        if let r = token.reduced { #expect(!r.isSpring) }
        #expect(token.curve(reduceMotion: true) == token.reduced)
        #expect(token.curve(reduceMotion: false) == token.curve)
    }
    #expect(MotionToken.arrive.reduced == .easeInOut(duration: 0.15))
    #expect(MotionToken.ambient.reduced == nil)
}
