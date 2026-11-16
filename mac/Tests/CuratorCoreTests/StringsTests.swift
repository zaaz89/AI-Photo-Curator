import Foundation
import Testing
@testable import CuratorCore

@Test func everyKeyHasBothLanguages() {
    for (key, pair) in Strings.table {
        #expect(!pair.0.isEmpty && !pair.1.isEmpty, "empty text for \(key)")
    }
}

/// Every string the app asks for exists: literal keys in the sources plus the dynamic families.
@Test func everyUsedKeyExists() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources")
    var keys = Set<String>()
    let regex = try Regex(#"(?:tr|text|row|pill)\("([A-Za-z_]+)""#)
    let quoted = try Regex(#"(?:tr|pill)\([^\n]*?\?\s*"([A-Za-z_]+)"\s*:\s*"([A-Za-z_]+)""#)
    for case let url as URL in FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)! where url.pathExtension == "swift" {
        let src = try String(contentsOf: url, encoding: .utf8)
        for m in src.matches(of: regex) { keys.insert(String(m.output[1].substring!)) }
        for m in src.matches(of: quoted) { keys.insert(String(m.output[1].substring!)); keys.insert(String(m.output[2].substring!)) }
    }
    keys.subtract(["phase_", "sort_", "tier_", "w_", "key", "ownerFrom_"])
    keys.formUnion(["ownerFrom_remembered", "ownerFrom_exif", "ownerFrom_folder"])
    keys.formUnion(ActivityPhase.allCases.map { "phase_" + $0.rawValue })
    keys.formUnion(PhotoSort.allCases.map { "sort_" + $0.rawValue })
    keys.formUnion(["tier_sharp", "tier_soft", "tier_blurry", "w_faces", "w_focus", "w_look", "w_resolution"])
    let missing = keys.filter { Strings.table[$0] == nil }.sorted()
    #expect(missing.isEmpty, "missing strings: \(missing)")
    #expect(keys.count > 80)
}

@Test func photoCountPlurals() {
    #expect(Strings.photos(1, .en) == "1 photo" && Strings.photos(5, .en) == "5 photos")
    #expect(Strings.photos(1, .sl) == "1 fotografija")
    #expect(Strings.photos(2, .sl) == "2 fotografiji")
    #expect(Strings.photos(3, .sl) == "3 fotografije" && Strings.photos(4, .sl) == "4 fotografije")
    #expect(Strings.photos(5, .sl) == "5 fotografij" && Strings.photos(11, .sl) == "11 fotografij")
    #expect(Strings.photos(101, .sl) == "101 fotografija" && Strings.photos(102, .sl) == "102 fotografiji")
    #expect(Strings.photos(0, .sl) == "0 fotografij")
}

/// A key written twice would crash the app when the table loads.
@Test func noDuplicateKeys() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/CuratorCore/Strings.swift")
    let src = try String(contentsOf: file, encoding: .utf8)
    let keys = src.matches(of: try Regex(#"(?m)^\s+"([^"]+)": \("#)).map { String($0.output[1].substring!) }
    let dupes = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
    #expect(dupes.isEmpty, "duplicate keys: \(dupes)")
    #expect(keys.count > 150)
}

@Test func countedWords() {
    #expect(Strings.count(1, .moment, .en) == "1 moment" && Strings.count(3, .moment, .en) == "3 moments")
    #expect(Strings.count(1, .moment, .sl) == "1 trenutek" && Strings.count(2, .moment, .sl) == "2 trenutka")
    #expect(Strings.count(4, .moment, .sl) == "4 trenutki" && Strings.count(5, .moment, .sl) == "5 trenutkov")
    #expect(Strings.count(2, .person, .sl) == "2 osebi" && Strings.count(3, .person, .sl) == "3 osebe")
    #expect(Strings.count(1, .day, .sl) == "1 dan" && Strings.count(2, .day, .sl) == "2 dneva" && Strings.count(5, .day, .sl) == "5 dni")
    #expect(Strings.count(2, .event, .sl) == "2 dogodka" && Strings.count(1, .video, .en) == "1 video")
}
