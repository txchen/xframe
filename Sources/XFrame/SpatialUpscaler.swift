import Metal
import MetalFX

// Exclusively leased to one submission; resolved only after its GPU completion.
final class SpatialCounter: @unchecked Sendable {
    let buffer: any MTLCounterSampleBuffer
    init(_ buffer: any MTLCounterSampleBuffer) { self.buffer = buffer }
}

// One tracked input/output pair is safe on the renderer's single serial command
// queue. Every command retains this generation until its final consumer finishes.
// Resizing replaces the generation; the three-submission cap bounds retired ones.
final class SpatialUpscaler: @unchecked Sendable {
    let input, output: any MTLTexture
    let scaler: any MTLFXSpatialScaler
    let sourceExtent, outputExtent: ScalingExtent
    private let lock = NSLock()
    private var counters: [SpatialCounter] = []

    init(device: any MTLDevice, source: ScalingExtent, output: ScalingExtent) throws {
        sourceExtent = source; outputExtent = output
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = source.width; descriptor.inputHeight = source.height
        descriptor.outputWidth = output.width; descriptor.outputHeight = output.height
        descriptor.colorTextureFormat = .bgra8Unorm
        descriptor.outputTextureFormat = .bgra8Unorm
        descriptor.colorProcessingMode = .perceptual
        guard MTLFXSpatialScalerDescriptor.supportsDevice(device),
              let scaler = descriptor.makeSpatialScaler(device: device) else {
            throw RenderError.unavailable("MetalFX Spatial is unavailable.")
        }
        self.scaler = scaler
        func texture(_ extent: ScalingExtent, usage: MTLTextureUsage) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: extent.width, height: extent.height, mipmapped: false)
            d.storageMode = .private
            d.usage = usage
            guard let result = device.makeTexture(descriptor: d) else {
                throw RenderError.unavailable("Cannot allocate MetalFX textures.")
            }
            return result
        }
        input = try texture(source, usage: scaler.colorTextureUsage.union([.renderTarget]))
        self.output = try texture(output, usage: scaler.outputTextureUsage.union([.shaderRead]))
        scaler.colorTexture = input; scaler.outputTexture = self.output
        scaler.inputContentWidth = source.width; scaler.inputContentHeight = source.height
        if device.supportsCounterSampling(.atStageBoundary),
           let set = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) {
            let d = MTLCounterSampleBufferDescriptor()
            d.counterSet = set; d.storageMode = .shared; d.sampleCount = 2
            for _ in 0..<3 {
                if let buffer = try? device.makeCounterSampleBuffer(descriptor: d) { counters.append(SpatialCounter(buffer)) }
            }
        }
    }

    func takeCounter() -> SpatialCounter? { lock.withLock { counters.popLast() } }
    func returnCounter(_ counter: SpatialCounter) { lock.withLock { counters.append(counter) } }

    // GPU interval from source conversion's fragment end to final composition's
    // fragment start. Includes MetalFX and inter-pass scheduling, not conversion or
    // display wait. Timestamp counters resolve to nanoseconds; missing stays nil.
    static func scalerSeconds(_ counter: SpatialCounter) -> Double? {
        guard let data = try? counter.buffer.resolveCounterRange(0..<2), data.count >= 16 else { return nil }
        return data.withUnsafeBytes { bytes in
            let start = bytes.loadUnaligned(fromByteOffset: 0, as: UInt64.self)
            let end = bytes.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
            guard start != 0, start != UInt64.max, end != UInt64.max, end >= start else { return nil }
            return Double(end - start) / 1_000_000_000
        }
    }
}
