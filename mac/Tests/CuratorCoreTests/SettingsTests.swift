import Foundation
import Testing
@testable import CuratorCore

@Test func speedEstimateMatchesTheEngine() {
    // The engine's estimate_seconds: photos x (other + throttled x 100 / share).
    let sp = EngineSpeed(throttledPerPhoto: 0.6, otherPerPhoto: 1.0, photos: 10)
    #expect(sp.seconds(photos: 100, share: 100) == 160)
    #expect(abs(sp.seconds(photos: 100, share: 30)! - 300) < 0.001)
    #expect(sp.seconds(photos: 0, share: 30) == nil)
    #expect(sp.seconds(photos: 10, share: 0) == sp.seconds(photos: 10, share: 1))     // never divides by zero
}

@Test func durationsReadAsRoughTimes() {
    #expect(Strings.duration(2, .en) == "about 5 s")
    #expect(Strings.duration(41, .en) == "about 40 s")
    #expect(Strings.duration(130, .sl) == "okoli 2 min")
    #expect(Strings.duration(4200, .en) == "about 1 h 10 min")
}

@Test func settingsDecodeWithAndWithoutStrictness() throws {
    let old = #"{"ui_language":"sl","ai_gpu_share":45,"ai_pause_on_battery":true,"keeper_weights":{"faces":40}}"#
    let s = try JSONDecoder().decode(EngineSettings.self, from: Data(old.utf8))
    #expect(s.aiGpuShare == 45 && s.qualityStrictness == "normal")
    let new = #"{"ui_language":"en","ai_gpu_share":30,"ai_pause_on_battery":false,"keeper_weights":{},"quality_strictness":"strict"}"#
    #expect(try JSONDecoder().decode(EngineSettings.self, from: Data(new.utf8)).qualityStrictness == "strict")
    let speed = #"{"throttled_per_photo":0.2,"other_per_photo":0.1,"photos":19,"measured_at":"x"}"#
    #expect(try JSONDecoder().decode(EngineSpeed.self, from: Data(speed.utf8)).photos == 19)
}

@Test func settingsPageThroughTheBackgroundChannel() {
    #expect(AutomationCommand(url: URL(string: "photocurator://go?page=settings")!) == .go("settings"))
}
