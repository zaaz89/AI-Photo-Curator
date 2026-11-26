import Foundation

// M12c (UX P0): the sorting stage's states, its limit for per-photo animation, VoiceOver labels and the texts
// of the undo toast. Pure functions, so the views and the tests agree.

/// Up to this many photos the stage animates every photo (fly in, verdict, stack). Above it the stage shows
/// the result at once in a scrollable grid by day: no per-photo animation, thumbnails load as they scroll in.
public let stageChoreographyLimit = 400

/// The stage plays its per-photo animation for this many photos.
public func stageAnimatesEachPhoto(_ count: Int) -> Bool { count <= stageChoreographyLimit }

/// What the stage header says.
public enum StageState: Equatable, Sendable {
    /// The analysis runs.
    case running
    /// The analysis of this album ended with an error (the engine's reason).
    case failed(reason: String)
    /// No analysis runs, but some photos are not analysed yet (stopped by the owner, or the engine restarted).
    case stopped(remaining: Int)
    /// No photos yet.
    case waiting
    /// The analysis is over; the stage may still be playing.
    case done

    /// A state with a primary "Resume" or "Analyse again".
    public var needsRestart: Bool {
        switch self { case .failed, .stopped: true; default: false }
    }
}

/// The stage's state from the engine's job and the album's photos (the second file of a pair excluded).
public func stageState(job: JobStatus, analysing: Bool, trip: String?, photos: [Photo]) -> StageState {
    if analysing { return .running }
    let mine = job.collection == nil || job.collection == trip
    if mine && (job.kind ?? "analysis") == "analysis" && job.phase == .failed {
        return .failed(reason: failureReason(job))
    }
    if photos.isEmpty { return .waiting }
    // Stopped: the last job of this album was cancelled, or none ran since the engine started. After a job that
    // finished ("Done in …") photos without results are files the engine could not read: not a stop.
    let remaining = photos.filter { !hasResults($0) }.count
    let interrupted = mine && (job.status.isEmpty || job.status.hasPrefix("Cancelled"))
    return remaining > 0 && interrupted ? .stopped(remaining: remaining) : .done
}

/// The engine's error without its "Error: " prefix, on one line.
public func failureReason(_ job: JobStatus) -> String {
    var r = job.error ?? job.status
    if r.hasPrefix("Error: ") { r = String(r.dropFirst(7)) }
    return r.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
}

/// Header title and subtitle for a state that is not a running act (`nil`: the act's own title shows).
public func stageStateTexts(_ state: StageState, _ lang: Lang) -> (title: String, subtitle: String)? {
    switch state {
    case .failed(let reason):
        let sub = Strings.text("stageFailedSub", lang)
        return (Strings.text("stageFailed", lang), reason.isEmpty ? sub : reason + " · " + sub)
    case .stopped(let n):
        return (Strings.text("stageStopped", lang), String(format: Strings.text("stageStoppedSub", lang), Strings.count(n, .photo, lang)))
    default:
        return nil
    }
}

// MARK: VoiceOver

/// What a verdict means in words ("In the album", "Left out", …).
public func verdictText(_ v: SortVerdict, _ lang: Lang) -> String {
    v == .album ? Strings.text("inAlbum", lang) : Strings.text("tray_" + v.rawValue, lang)
}

/// Why a photo is where it is, in words ("Blurred by movement", "You left it out"), or nil.
public func sortReasonText(_ p: Photo, _ lang: Lang) -> String? {
    guard let code = sortReason(p) else { return nil }
    if code == "leftOut" { return Strings.text("reason_leftOut", lang) }
    let t = Strings.text("why2_" + code, lang)
    return t == "why2_" + code ? code : t
}

/// VoiceOver label of a photo on the sorting stage: file, verdict, reason, frames stacked behind it, video.
/// `verdict` is nil while the stage has not shown it yet.
public func stageTileAccessibilityLabel(_ p: Photo, verdict: SortVerdict?, stacked: Int, _ lang: Lang) -> String {
    var parts = [p.filename]
    if let verdict {
        parts.append(verdictText(verdict, lang))
        if let r = sortReasonText(p, lang) { parts.append(r) }
    } else {
        parts.append(Strings.text("a11yNotSorted", lang))
    }
    if stacked > 0 { parts.append(String(format: Strings.text("a11yStackedBehind", lang), Strings.count(stacked, .photo, lang))) }
    if p.isVideo { parts.append(Strings.text("video", lang)) }
    return parts.filter { !$0.isEmpty }.joined(separator: ", ")
}

/// VoiceOver label of a photo in a grid: file, time, owner, then every status the tile shows as a badge
/// (favourite, left out, focus tier, eyes closed, another frame, not in the album with its reason).
public func gridTileAccessibilityLabel(_ p: Photo, _ lang: Lang) -> String {
    var parts = [p.filename, p.clock, p.owner]
    if p.favorite { parts.append(Strings.text("favourite", lang)) }
    if p.rejected {
        parts.append(Strings.text("leftOut", lang))
    } else if !p.goesToAlbumDespiteFocus {
        parts.append(Strings.text("notInAlbum", lang))
        if let r = sortReasonText(p, lang) { parts.append(r) }
    }
    if let tier = p.focus?.tier, tier != "sharp", !p.isVideo { parts.append(Strings.text("tier_" + tier, lang)) }
    if (p.faces?.eyesClosed ?? 0) > 0 { parts.append(Strings.text("eyesClosed", lang)) }
    if p.duplicate?.keeper == false { parts.append(Strings.text("extraFrame", lang)) }
    if p.isVideo { parts.append(Strings.text("video", lang)) }
    var seen = Set<String>()
    return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ", ")
}

// MARK: undo toast

/// A reversible action the undo toast confirms.
public enum UndoableAction: String, Sendable {
    case putBack, leaveOut, keptInAlbum
}

/// "Put back 3 photos" / "Vrnjeno v album: 3 fotografije".
public func undoToastText(_ action: UndoableAction, count: Int, _ lang: Lang) -> String {
    String(format: Strings.text("toast_" + action.rawValue, lang), Strings.count(count, .photo, lang))
}
