import AVFoundation
import AppKit
import CoreMedia
import SwiftUI

/// Turns the phone's H.264 events into frames on a display layer, which decodes them in hardware.
final class H264Presenter: @unchecked Sendable {
    private let layer: AVSampleBufferDisplayLayer
    private let queue = DispatchQueue(label: "phone.display.present")
    private var format: CMVideoFormatDescription?

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    /// True once a configuration packet produced a usable format. Waits for pending work, so tests can read it.
    var hasFormat: Bool { queue.sync { format != nil } }

    func handle(_ event: ScrcpyEvent) {
        queue.async { [self] in
            switch event {
            case .session:
                // A new session (first one, or the phone rotated) starts over with its own configuration.
                format = nil
                layer.sampleBufferRenderer.flush(removingDisplayedImage: false)
            case .config(let data):
                if let made = Self.makeFormat(fromConfig: data) {
                    format = made
                }
            case .frame(let data, let keyFrame, let pts):
                present(data, keyFrame: keyFrame, ptsMicros: pts)
            case .deviceName:
                break
            }
        }
    }

    func reset() {
        queue.async { [self] in
            format = nil
            layer.sampleBufferRenderer.flush(removingDisplayedImage: true)
        }
    }

    private static func makeFormat(fromConfig data: Data) -> CMVideoFormatDescription? {
        guard let sets = H264.parameterSets(fromConfig: data) else { return nil }
        var description: CMVideoFormatDescription?
        let status = sets.sps.withUnsafeBytes { sps in
            sets.pps.withUnsafeBytes { pps -> OSStatus in
                guard let spsBase = sps.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = pps.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                let pointers = [spsBase, ppsBase]
                let sizes = [sets.sps.count, sets.pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        return status == noErr ? description : nil
    }

    private func present(_ data: Data, keyFrame: Bool, ptsMicros: UInt64) {
        guard let format else { return }
        let payload = H264.lengthPrefixed(fromAnnexB: data)
        guard !payload.isEmpty else { return }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: payload.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: payload.count, flags: 0,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return }
        let copied = payload.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard copied == kCMBlockBufferNoErr else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: Int64(ptsMicros), timescale: 1_000_000),
                                        decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
           let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
            if !keyFrame { first[kCMSampleAttachmentKey_NotSync] = true }
        }
        let renderer = layer.sampleBufferRenderer
        // A decoder error leaves the layer unusable until it is flushed; the next key frame recovers it.
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }
}

/// What the phone window shows and how it sends input back. Owned by ScreenMirror.
@MainActor
final class PhoneDisplayModel: ObservableObject {
    let layer = AVSampleBufferDisplayLayer()
    private let presenter: H264Presenter
    @Published private(set) var videoSize: CGSize = .zero
    /// Sends a control message to the phone.
    var send: ((Data) -> Void)?

    init() { presenter = H264Presenter(layer: layer) }

    nonisolated func handle(_ event: ScrcpyEvent) {
        presenter.handle(event)
        if case let .session(width, height) = event {
            Task { @MainActor [weak self] in self?.videoSize = CGSize(width: width, height: height) }
        }
    }

    func reset() {
        presenter.reset()
        videoSize = .zero
        send = nil
    }
}

/// The phone's screen. Clicks and drags become touches, the wheel scrolls, a right click is Back, and typing is sent as text.
struct PhoneDisplay: NSViewRepresentable {
    let model: PhoneDisplayModel

    func makeNSView(context: Context) -> PhoneDisplayView { PhoneDisplayView(model: model) }
    func updateNSView(_ view: PhoneDisplayView, context: Context) {}
}

final class PhoneDisplayView: NSView {
    private let model: PhoneDisplayModel
    private var touching = false
    private var lastPoint: (x: Int32, y: Int32)?

    init(model: PhoneDisplayModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func makeBackingLayer() -> CALayer { MainActor.assumeIsolated { model.layer } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var videoSize: CGSize { MainActor.assumeIsolated { model.videoSize } }

    private func point(of event: NSEvent) -> (x: Int32, y: Int32)? {
        ScrcpyLaunch.devicePoint(viewPoint: convert(event.locationInWindow, from: nil), viewSize: bounds.size, videoSize: videoSize)
    }

    private func send(_ data: Data) { MainActor.assumeIsolated { model.send?(data) } }

    private func touch(_ action: UInt8, at point: (x: Int32, y: Int32), pressed: Bool) {
        let size = videoSize
        send(ScrcpyControl.touch(action: action, x: point.x, y: point.y, width: UInt16(size.width), height: UInt16(size.height),
                                 pressed: pressed))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = point(of: event) else { return }
        touching = true
        lastPoint = point
        touch(ScrcpyControl.Action.down, at: point, pressed: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard touching else { return }
        // Leaving the picture keeps the finger where it left, instead of jumping.
        let point = point(of: event) ?? lastPoint
        guard let point else { return }
        lastPoint = point
        touch(ScrcpyControl.Action.move, at: point, pressed: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard touching else { return }
        touching = false
        let point = point(of: event) ?? lastPoint
        if let point { touch(ScrcpyControl.Action.up, at: point, pressed: false) }
        lastPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // Back, and it wakes the phone when the screen is off.
        send(ScrcpyControl.backOrScreenOn(action: ScrcpyControl.Action.down))
        send(ScrcpyControl.backOrScreenOn(action: ScrcpyControl.Action.up))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let point = point(of: event) else { return }
        let size = videoSize
        // Trackpads report pixels; a wheel step is about ten of them.
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 10 : 1
        send(ScrcpyControl.scroll(x: point.x, y: point.y, width: UInt16(size.width), height: UInt16(size.height),
                                  horizontal: Float(event.scrollingDeltaX / unit), vertical: Float(event.scrollingDeltaY / unit)))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        let keys: [UInt16: Int32] = [36: ScrcpyControl.Key.enter, 76: ScrcpyControl.Key.enter, 51: ScrcpyControl.Key.delete,
                                     48: ScrcpyControl.Key.tab, 53: ScrcpyControl.Key.back, 123: ScrcpyControl.Key.dpadLeft,
                                     124: ScrcpyControl.Key.dpadRight, 125: ScrcpyControl.Key.dpadDown, 126: ScrcpyControl.Key.dpadUp]
        if let key = keys[event.keyCode] {
            send(ScrcpyControl.keycode(action: ScrcpyControl.Action.down, keycode: key))
            send(ScrcpyControl.keycode(action: ScrcpyControl.Action.up, keycode: key))
        } else if let text = event.characters, let message = ScrcpyControl.text(text),
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            send(message)
        }
    }
}
