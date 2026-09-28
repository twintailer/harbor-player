import AVFoundation
import CoreGraphics
import Foundation

// Deterministic, locally generated video. No network sample or user media.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)
for frame in 0..<900 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pixel = buffer!
    CVPixelBufferLockBaseAddress(pixel, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(red: 0.04, green: 0.08, blue: 0.12, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
    context.setFillColor(CGColor(red: 0.36, green: 0.92, blue: 0.74, alpha: 1)); context.fillEllipse(in: CGRect(x: 50 + frame % 450, y: 120, width: 100, height: 100))
    CVPixelBufferUnlockBaseAddress(pixel, [])
    precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
}
input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }; semaphore.wait()
precondition(writer.status == .completed, writer.error?.localizedDescription ?? "Fixture encoding failed")
