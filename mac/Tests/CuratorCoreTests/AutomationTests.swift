import Foundation
import Testing
@testable import CuratorCore

@Test func automationCommandsParse() {
    func c(_ s: String) -> AutomationCommand? { AutomationCommand(url: URL(string: s)!) }
    #expect(c("photocurator://go?page=selection") == .go("selection"))
    #expect(c("photocurator://album?id=test-10") == .album("test-10"))
    #expect(c("photocurator://review") == .review(.decisions))
    #expect(c("photocurator://review?filter=all") == .review(.all))
    #expect(c("photocurator://review?close=1") == .closeReview)
    #expect(c("photocurator://key?k=right") == .key("right"))
    #expect(c("photocurator://window?w=1500&h=980") == .window(width: 1500, height: 980))
    #expect(c("photocurator://reload") == .reload)
    // Anything unknown or malformed is refused.
    #expect(c("photocurator://go?page=finder") == nil)
    #expect(c("photocurator://key?k=delete-all") == nil)
    #expect(c("photocurator://window?w=99999&h=1") == nil)
    #expect(c("photocurator://finish") == nil)
    #expect(c("https://go?page=home") == nil)
}
