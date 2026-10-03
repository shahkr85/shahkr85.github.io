// Resize photos for the web and drop all metadata (EXIF, GPS), keeping the color profile.
// Writes <outDir>/full (2000px) and <outDir>/thumbs (900px), plus <outDir>/generated.json
// with each photo's paths and size, to copy into Pictures/Photography/photos.json
// (prefix paths with "web/" and add title/category/alt/meta).
//
// usage: swift tools/resize-photos.swift Pictures/Photography Pictures/Photography/web
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let fm = FileManager.default
for d in ["full", "thumbs"] { try? fm.createDirectory(at: out.appendingPathComponent(d), withIntermediateDirectories: true) }

func clean(_ stem: String) -> String {
    var s = stem.lowercased().replacingOccurrences(of: " (1)", with: "")
    if s.hasPrefix("dji_fly_") {
        let parts = s.split(separator: "_")
        if parts.count > 4 { s = "dji_" + parts[4] }
    } else if s.count == 36 && s.contains("-") {
        s = "photo_" + s.prefix(8)
    }
    return s.replacingOccurrences(of: "[^a-z0-9_-]", with: "_", options: .regularExpression)
}

func write(_ srcURL: URL, _ dst: URL, maxPx: Int, q: Double) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(srcURL as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPx,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
          let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return (img.width, img.height)
}

var entries: [[String: Any]] = []
let files = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
    .filter { ["jpeg", "jpg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var thumbs: [(String, CGImage)] = []
for f in files {
    let name = clean(f.deletingPathExtension().lastPathComponent) + ".jpg"
    guard let (w, h) = write(f, out.appendingPathComponent("full/" + name), maxPx: 2000, q: 0.8),
          write(f, out.appendingPathComponent("thumbs/" + name), maxPx: 900, q: 0.72) != nil else {
        print("FAILED", f.lastPathComponent); continue
    }
    entries.append(["file": "full/" + name, "thumb": "thumbs/" + name, "width": w, "height": h])
    print(name, w, h)
}

let json = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted])
try json.write(to: out.appendingPathComponent("generated.json"))
