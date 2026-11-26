import AVFoundation
import CoreMedia
import CoreVideo
@testable import NexusMasterSync
import VideoToolbox
import XCTest

final class PhoneDisplayTests: XCTestCase {
    /// One real H.264 key frame (64x64) from VideoToolbox, as Annex B: what the phone's encoder would send.
    private func encodeOneFrame() throws -> (config: Data, frame: Data) {
        var session: VTCompressionSession?
        guard VTCompressionSessionCreate(allocator: nil, width: 64, height: 64, codecType: kCMVideoCodecType_H264,
                                         encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                         outputCallback: nil, refcon: nil, compressionSessionOut: &session) == noErr,
              let session else { throw XCTSkip("Sem codificador H.264 neste ambiente.") }
        defer { VTCompressionSessionInvalidate(session) }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixels)
        let buffer = try XCTUnwrap(pixels)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 0x80, CVPixelBufferGetDataSize(buffer)) }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let done = expectation(description: "encoded")
        var annexB = Data(), config = Data()
        let start: [UInt8] = [0, 0, 0, 1]
        VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: .zero, duration: .invalid,
                                        frameProperties: nil, infoFlagsOut: nil) { _, _, sample in
            defer { done.fulfill() }
            guard let sample, let format = CMSampleBufferGetFormatDescription(sample) else { return }
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                                                                   parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                   nalUnitHeaderLengthOut: nil)
                if let pointer { config.append(contentsOf: start); config.append(pointer, count: size) }
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
            var length = 0
            var data: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &data)
            guard let data else { return }
            let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: length)
            var offset = 0
            while offset + 4 <= bytes.count {
                let size = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
                offset += 4
                guard size > 0, offset + size <= bytes.count else { break }
                annexB.append(contentsOf: start)
                annexB.append(contentsOf: bytes[offset..<offset + size])
                offset += size
            }
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        wait(for: [done], timeout: 5)
        guard !config.isEmpty, !annexB.isEmpty else { throw XCTSkip("O codificador não devolveu um quadro.") }
        return (config, annexB)
    }

    func testPresenterBuildsAFormatFromConfigAndAcceptsFrames() throws {
        let (config, frame) = try encodeOneFrame()
        let layer = AVSampleBufferDisplayLayer()
        let presenter = H264Presenter(layer: layer)
        presenter.handle(.session(width: 64, height: 64))
        presenter.handle(.config(config))
        presenter.handle(.frame(frame, keyFrame: true, ptsMicros: 0))
        XCTAssertTrue(presenter.hasFormat)
        XCTAssertNotEqual(layer.sampleBufferRenderer.status, .failed)
    }

    func testSessionPacketResetsTheFormat() throws {
        let (config, _) = try encodeOneFrame()
        let presenter = H264Presenter(layer: AVSampleBufferDisplayLayer())
        presenter.handle(.config(config))
        XCTAssertTrue(presenter.hasFormat)
        presenter.handle(.session(width: 128, height: 64))
        XCTAssertFalse(presenter.hasFormat)
    }

    func testFramesBeforeAnyConfigAreDropped() throws {
        let (_, frame) = try encodeOneFrame()
        let layer = AVSampleBufferDisplayLayer()
        let presenter = H264Presenter(layer: layer)
        presenter.handle(.frame(frame, keyFrame: true, ptsMicros: 0))
        XCTAssertFalse(presenter.hasFormat)
        XCTAssertNotEqual(layer.sampleBufferRenderer.status, .failed)
    }

    func testUnusableConfigKeepsThePresenterWithoutAFormat() {
        let presenter = H264Presenter(layer: AVSampleBufferDisplayLayer())
        presenter.handle(.config(Data([0, 0, 0, 1, 0x67, 1])))
        XCTAssertFalse(presenter.hasFormat)
        presenter.handle(.config(Data()))
        XCTAssertFalse(presenter.hasFormat)
    }
}
