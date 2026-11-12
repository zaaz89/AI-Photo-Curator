// PhotoCuratorHelper: on-device Apple frameworks for AI Photo Curator.
//
//   pc-helper faces            reads image paths (one per line) on stdin, prints one JSON line per image:
//                              {"path", "faces": [{"quality", "yaw", "roll", "pitch", "left_eye", "right_eye",
//                                "box": [x, y, w, h]}], "error"}
//   pc-helper video <out-dir>  reads video paths on stdin, writes a JPEG poster frame per video into out-dir,
//                              prints {"path", "duration", "width", "height", "created", "thumb", "error"}
//
// Apple Vision runs on the Neural Engine; nothing leaves the Mac. Faces are not identified:
// only quality, head angle and eye openness are measured. Files are opened read-only.
import AppKit
import AVFoundation
import Foundation
import Vision

func emit(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
}

/// Eye openness: height of the eye contour divided by its width (about 0.2-0.35 open, < 0.12 closed).
func eyeOpenness(_ region: VNFaceLandmarkRegion2D?) -> Double? {
    guard let pts = region?.normalizedPoints, pts.count >= 4 else { return nil }
    let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
    let w = (xs.max()! - xs.min()!), h = (ys.max()! - ys.min()!)
    return w > 0 ? h / w : nil
}

func faces(_ path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    let landmarks = VNDetectFaceLandmarksRequest()
    let quality = VNDetectFaceCaptureQualityRequest()
    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
        try handler.perform([landmarks, quality])
    } catch {
        return ["path": path, "faces": [], "error": "\(error.localizedDescription)"]
    }
    let lm = landmarks.results ?? []
    let q = quality.results ?? []
    var out: [[String: Any]] = []
    for face in lm {
        // match the quality observation by bounding box overlap
        let match = q.min(by: { a, b in
            abs(a.boundingBox.midX - face.boundingBox.midX) + abs(a.boundingBox.midY - face.boundingBox.midY) <
            abs(b.boundingBox.midX - face.boundingBox.midX) + abs(b.boundingBox.midY - face.boundingBox.midY)
        })
        let b = face.boundingBox
        var f: [String: Any] = ["box": [b.origin.x, b.origin.y, b.width, b.height].map { Double($0) }]
        if let fq = match?.faceCaptureQuality { f["quality"] = Double(fq) }
        if let yaw = face.yaw { f["yaw"] = yaw.doubleValue }
        if let roll = face.roll { f["roll"] = roll.doubleValue }
        if let pitch = face.pitch { f["pitch"] = pitch.doubleValue }
        if let l = eyeOpenness(face.landmarks?.leftEye) { f["left_eye"] = l }
        if let r = eyeOpenness(face.landmarks?.rightEye) { f["right_eye"] = r }
        out.append(f)
    }
    return ["path": path, "faces": out]
}

func video(_ path: String, outDir: URL) -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    var result: [String: Any] = ["path": path]
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let duration = try await asset.load(.duration)
            result["duration"] = CMTimeGetSeconds(duration)
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let t = try await track.load(.preferredTransform)
                let r = size.applying(t)
                result["width"] = abs(Double(r.width))
                result["height"] = abs(Double(r.height))
            }
            if let created = try await asset.load(.creationDate), let d = try await created.load(.dateValue) {
                result["created"] = ISO8601DateFormatter().string(from: d)
            }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 640, height: 640)
            let at = CMTime(seconds: min(1.0, CMTimeGetSeconds(duration) / 2), preferredTimescale: 600)
            let (cg, _) = try await gen.image(at: at)
            let rep = NSBitmapImageRep(cgImage: cg)
            if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                let name = String(path.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
                let out = outDir.appendingPathComponent("\(name).jpg")
                try jpg.write(to: out)
                result["thumb"] = out.path
            }
        } catch {
            result["error"] = "\(error.localizedDescription)"
        }
        sem.signal()
    }
    sem.wait()
    return result
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: pc-helper faces | pc-helper video <out-dir>\n".data(using: .utf8)!)
    exit(2)
}
var paths: [String] = []
while let line = readLine() {
    let p = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if !p.isEmpty { paths.append(p) }
}
switch args[1] {
case "faces":
    for p in paths { autoreleasepool { emit(faces(p)) } }
case "video":
    guard args.count >= 3 else { exit(2) }
    let dir = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for p in paths { emit(video(p, outDir: dir)) }
case "version":
    emit(["version": "1"])
default:
    exit(2)
}
