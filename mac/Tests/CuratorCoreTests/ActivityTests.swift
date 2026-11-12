import Foundation
import Testing
@testable import CuratorCore

@Test(arguments: [
    ("Faces (Apple Vision) (3/19)", ActivityPhase.faces),
    ("Describing photos (about 8 s each) (2/10)", .describing),
    ("Search index (SigLIP 2)", .searchIndex),
    ("Visual signatures: IMG_1.JPG (4/19)", .duplicates),
    ("Copying and verifying (5/18)", .exporting),
    ("Paused: the Mac is warm", .paused),
    ("Something new", .working),
])
func phaseFromStatus(status: String, phase: ActivityPhase) {
    #expect(JobStatus(running: true, status: status).phase == phase)
}

@Test func idleAndErrors() {
    #expect(JobStatus(running: false, status: "Done").phase == .idle)
    #expect(JobStatus(running: false, status: "Error: disk full", error: "disk full").phase == .failed)
    #expect(ActivityPhase.faces.isAI && !ActivityPhase.exporting.isAI)
}

@Test func counter() {
    #expect(JobStatus(running: true, status: "Faces (Apple Vision) (3/19)").counter! == (3, 19))
    #expect(JobStatus(running: true, status: "Search index (SigLIP 2)").counter == nil)
}
