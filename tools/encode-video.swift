// Make a web copy of a video: H.264 MP4, 960px long edge, ~1.1 Mbps, no audio,
// no metadata (strips GPS), plus a poster image (same name, .jpg) from 1s in.
//
// usage: swift tools/encode-video.swift <source video> <output .mp4> [longEdge] [bitsPerSecond]
// e.g.   swift tools/encode-video.swift "Pictures/Photography/clip.mov" Pictures/Photography/web/video/drone-1.mp4
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 3 else {
    print("usage: swift tools/encode-video.swift <source video> <output .mp4> [longEdge] [bitsPerSecond]")
    exit(1)
}
let srcURL = URL(fileURLWithPath: a[1])
let outURL = URL(fileURLWithPath: a[2])
let posterURL = outURL.deletingPathExtension().appendingPathExtension("jpg")
let longEdge = a.count > 3 ? Double(a[3])! : 960
let bitrate = a.count > 4 ? Int(a[4])! : 1_100_000
try? FileManager.default.removeItem(at: outURL)

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let asset = AVURLAsset(url: srcURL)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)

        let scale = longEdge / Double(max(natural.width, natural.height))
        let w = Int((Double(natural.width) * scale / 2).rounded()) * 2
        let h = Int((Double(natural.height) * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let rOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        rOut.alwaysCopiesSampleData = false
        reader.add(rOut)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []
        let wIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(max(fps, 24)) * 2,
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            ],
        ])
        wIn.transform = transform
        wIn.expectsMediaDataInRealTime = false
        writer.add(wIn)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let q = DispatchQueue(label: "enc")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wIn.requestMediaDataWhenReady(on: q) {
                while wIn.isReadyForMoreMediaData {
                    if let buf = rOut.copyNextSampleBuffer() {
                        wIn.append(buf)
                    } else {
                        wIn.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            print("failed \(String(describing: writer.error))"); exit(1)
        }

        // Poster frame (shown before the video loads).
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: outURL))
        gen.appliesPreferredTrackTransform = true
        let (cg, _) = try await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        let dest = CGImageDestinationCreateWithURL(posterURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(dest)

        let duration = try await asset.load(.duration).seconds
        let mb = Double((try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0) / 1_000_000
        print(String(format: "done: %@ (%dx%d, %.1fs, %.1f MB) + poster %@", outURL.lastPathComponent, w, h, duration, mb, posterURL.lastPathComponent))
    } catch {
        print("error", error)
    }
    sem.signal()
}
sem.wait()
