import AVFoundation
import CoreImage
import CoreML
import CryptoKit
import Foundation
import Metal
import QuartzCore

enum CoreMLFGProfile: String, CaseIterable, Sendable {
    case p720 = "coreml720"
    case p1080Balanced = "coreml1080Balanced"
    case p1080Quality = "coreml1080Quality"
    case p1440Balanced = "coreml1440Balanced"
    case p1440Quality = "coreml1440Quality"

    var id: String { rawValue }
    var width: Int {
        switch self {
        case .p720: 1280
        case .p1080Balanced, .p1080Quality: 1920
        case .p1440Balanced, .p1440Quality: 2560
        }
    }
    var height: Int {
        switch self {
        case .p720: 720
        case .p1080Balanced, .p1080Quality: 1080
        case .p1440Balanced, .p1440Quality: 1440
        }
    }
    var scale: Int {
        switch self {
        case .p720, .p1080Quality, .p1440Quality: 2
        case .p1080Balanced, .p1440Balanced: 3
        }
    }
    var paddedWidth: Int { ((width / scale + 15) / 16) * 16 }
    var paddedHeight: Int { ((height / scale + 15) / 16) * 16 }
    var shapeLabel: String { "\(paddedHeight)x\(paddedWidth)" }

    var title: String {
        switch self {
        case .p720: "Core ML FG 720p (Quality · 360p flow)"
        case .p1080Balanced: "Core ML FG 1080p (Balanced · 360p flow)"
        case .p1080Quality: "Core ML FG 1080p (Quality · 540p flow)"
        case .p1440Balanced: "Core ML FG 1440p (Balanced · 480p flow)"
        case .p1440Quality: "Core ML FG 1440p (Quality · 720p flow)"
        }
    }

    var shortTitle: String {
        switch self {
        case .p720: "720p"
        case .p1080Balanced: "1080p Balanced (360p flow)"
        case .p1080Quality: "1080p Quality (540p flow)"
        case .p1440Balanced: "1440p Balanced (480p flow)"
        case .p1440Quality: "1440p Quality (720p flow)"
        }
    }
}

struct SafetensorsFile {
    struct Entry: Decodable {
        let dtype: String
        let shape: [Int]
        let data_offsets: [Int]
    }

    let data: Data
    let payloadStart: Int
    let entries: [String: Entry]

    init(data: Data) throws {
        guard data.count >= 8 else {
            throw RenderError.unavailable("Safetensors file is truncated.")
        }
        let headerLength = data.withUnsafeBytes { raw -> UInt64 in
            raw.loadUnaligned(as: UInt64.self).littleEndian
        }
        let start = 8 + Int(headerLength)
        guard headerLength > 0, start <= data.count else {
            throw RenderError.unavailable("Safetensors header length is invalid.")
        }
        let headerData = data.subdata(in: 8..<start)
        guard let rawMap = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw RenderError.unavailable("Safetensors header is not a JSON object.")
        }
        var parsed: [String: Entry] = [:]
        let decoder = JSONDecoder()
        for (key, value) in rawMap where key != "__metadata__" {
            let entryData = try JSONSerialization.data(withJSONObject: value)
            parsed[key] = try decoder.decode(Entry.self, from: entryData)
        }
        self.data = data
        self.payloadStart = start
        self.entries = parsed
    }

    func slice(tensor name: String, byteOffset: Int, byteLength: Int) throws -> Data {
        guard let entry = entries[name], entry.data_offsets.count == 2 else {
            throw RenderError.unavailable("Missing tensor \(name) in safetensors weights.")
        }
        let tensorStart = payloadStart + entry.data_offsets[0]
        let tensorEnd = payloadStart + entry.data_offsets[1]
        let sliceStart = tensorStart + byteOffset
        let sliceEnd = sliceStart + byteLength
        guard sliceStart >= tensorStart, sliceEnd <= tensorEnd, sliceEnd <= data.count else {
            throw RenderError.unavailable("Tensor slice out of bounds for \(name).")
        }
        return data.subdata(in: sliceStart..<sliceEnd)
    }
}

struct CoreMLFGWeightLayout: Decodable {
    struct Chunk: Decodable {
        let metaOffset: Int
        let dataOffset: Int
        let byteLength: Int
        let tensor: String
        let tensorByteOffset: Int
    }
    struct Stage: Decodable {
        let totalBytes: Int
        let chunks: [Chunk]
    }
    let block0: Stage
    let block1: Stage

    func stage(_ index: Int) -> Stage { index == 0 ? block0 : block1 }

    func buildWeightBin(stageIndex: Int, from safetensors: SafetensorsFile) throws -> Data {
        let stage = stage(stageIndex)
        var buffer = Data(count: stage.totalBytes)
        buffer.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: UInt32(stage.chunks.count).littleEndian, toByteOffset: 0, as: UInt32.self)
            raw.storeBytes(of: UInt32(2).littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        for chunk in stage.chunks {
            let payload = try safetensors.slice(
                tensor: chunk.tensor,
                byteOffset: chunk.tensorByteOffset,
                byteLength: chunk.byteLength
            )
            buffer.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: UInt32(0xDEADBEEF).littleEndian, toByteOffset: chunk.metaOffset, as: UInt32.self)
                raw.storeBytes(of: UInt32(1).littleEndian, toByteOffset: chunk.metaOffset + 4, as: UInt32.self)
                raw.storeBytes(of: UInt64(chunk.byteLength).littleEndian, toByteOffset: chunk.metaOffset + 8, as: UInt64.self)
                raw.storeBytes(of: UInt64(chunk.dataOffset).littleEndian, toByteOffset: chunk.metaOffset + 16, as: UInt64.self)
            }
            buffer.replaceSubrange(chunk.dataOffset..<(chunk.dataOffset + chunk.byteLength), with: payload)
        }
        return buffer
    }
}

private struct FGBiasUniform {
    var b0: (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0, 0, 0, 0, 0)
    var b1: (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0, 0, 0, 0, 0)
}

enum CoreMLFrameGenerationBenchmark {
    static let budgetMS = 1000.0 / 30.0
    private static let warmupPairs = 5

    static func templateDirectory(in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: "CoreMLFG", withExtension: nil) else {
            throw RenderError.unavailable("Bundled Core ML FG templates are missing from XFrame.")
        }
        return url
    }

    static func compiledModelCacheDirectory(weightsDigest: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFrame/BenchmarkModels/CoreML", isDirectory: true)
            .appendingPathComponent(String(weightsDigest.prefix(12)), isDirectory: true)
    }

    static func measure(
        profile: CoreMLFGProfile,
        frames: [CVPixelBuffer],
        weightsURL: URL,
        resourceBundle: Bundle
    ) throws -> BenchmarkMeasurement {
        let pairCount = frames.count - 1
        guard pairCount > warmupPairs else {
            throw RenderError.unavailable("Not enough frames for Core ML FG benchmark.")
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw RenderError.unavailable("Metal device is unavailable.")
        }

        let templateRoot = try templateDirectory(in: resourceBundle)
        let shaderURL = templateRoot.appendingPathComponent("CoreMLFG.metal")
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let pipeNames = ["fgCandidates", "fgFeatures", "fgMergeFields", "fgCompose"]
        let pipes: [any MTLComputePipelineState] = try pipeNames.map { name in
            guard let fn = library.makeFunction(name: name) else {
                throw RenderError.unavailable("Missing Metal kernel \(name) in CoreMLFG.metal.")
            }
            return try device.makeComputePipelineState(function: fn)
        }

        let weightsData = try Data(contentsOf: weightsURL)
        let weightsDigest = SHA256.hash(data: weightsData).map { String(format: "%02x", $0) }.joined()
        let safetensors = try SafetensorsFile(data: weightsData)
        let layoutURL = templateRoot.appendingPathComponent("weight-layout.json")
        let layout = try JSONDecoder().decode(CoreMLFGWeightLayout.self, from: Data(contentsOf: layoutURL))

        var biasUniform = try makeBiasUniform(from: safetensors)
        let cacheRoot = compiledModelCacheDirectory(weightsDigest: weightsDigest)
        let b0URL = try ensureCompiledModel(
            stageIndex: 0, shapeLabel: profile.shapeLabel,
            templateRoot: templateRoot, layout: layout, safetensors: safetensors, cacheRoot: cacheRoot
        )
        let b1URL = try ensureCompiledModel(
            stageIndex: 1, shapeLabel: profile.shapeLabel,
            templateRoot: templateRoot, layout: layout, safetensors: safetensors, cacheRoot: cacheRoot
        )

        try Task.checkCancellation()

        let w = profile.width
        let h = profile.height
        let pw = profile.paddedWidth
        let ph = profile.paddedHeight
        let scale = profile.scale

        func makeTexture() throws -> any MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: desc) else {
                throw RenderError.unavailable("Cannot allocate Metal texture for Core ML FG.")
            }
            return tex
        }

        struct SharedTensor {
            let buffer: any MTLBuffer
            let array: MLMultiArray
            init(device: any MTLDevice, rows: Int, cols: Int, channels: Int) throws {
                let count = rows * cols * channels
                guard let buf = device.makeBuffer(length: count * 2, options: .storageModeShared) else {
                    throw RenderError.unavailable("Cannot allocate shared Metal/CoreML tensor buffer.")
                }
                buffer = buf
                array = try MLMultiArray(
                    dataPointer: buf.contents(),
                    shape: [1, rows, cols, channels].map(NSNumber.init),
                    dataType: .float16,
                    strides: [count, cols * channels, channels, 1].map(NSNumber.init),
                    deallocator: nil
                )
            }
        }

        let cand = try SharedTensor(device: device, rows: ph, cols: pw, channels: 16)
        let coarse = try SharedTensor(device: device, rows: ph / 2, cols: pw / 2, channels: 8)
        let feat = try SharedTensor(device: device, rows: ph, cols: pw, channels: 18)
        let fine = try SharedTensor(device: device, rows: ph, cols: pw, channels: 8)
        let field = try SharedTensor(device: device, rows: ph, cols: pw, channels: 5)

        struct CompiledStage {
            let model: MLModel
            let input: MLDictionaryFeatureProvider
            let options: MLPredictionOptions
            let output: SharedTensor
            let outputKey: String

            init(compiledURL: URL, inputTensor: SharedTensor, outputTensor: SharedTensor) throws {
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .cpuAndNeuralEngine
                model = try MLModel(contentsOf: compiledURL, configuration: cfg)
                input = try MLDictionaryFeatureProvider(dictionary: ["x": inputTensor.array])
                output = outputTensor
                guard let key = model.modelDescription.outputDescriptionsByName.keys.first else {
                    throw RenderError.unavailable("Compiled Core ML FG stage has no output description.")
                }
                outputKey = key
                let opts = MLPredictionOptions()
                opts.outputBackings = [key: outputTensor.array]
                options = opts
            }

            func run() throws {
                let result = try model.prediction(from: input, options: options)
                guard result.featureValue(for: outputKey)?.multiArrayValue?.dataPointer == output.buffer.contents() else {
                    throw RenderError.unavailable("Core ML did not honor the shared Metal output backing.")
                }
            }
        }

        let stage0 = try CompiledStage(compiledURL: b0URL, inputTensor: cand, outputTensor: coarse)
        let stage1 = try CompiledStage(compiledURL: b1URL, inputTensor: feat, outputTensor: fine)

        let ciContext = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        func dispatch(
            _ cb: any MTLCommandBuffer,
            pipelineIndex: Int,
            textures: [any MTLTexture],
            buffers: [any MTLBuffer],
            includeBias: Bool = false,
            fullRes: Bool = false
        ) {
            let encoder = cb.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipes[pipelineIndex])
            for (idx, tex) in textures.enumerated() { encoder.setTexture(tex, index: idx) }
            for (idx, buf) in buffers.enumerated() { encoder.setBuffer(buf, offset: 0, index: idx) }
            var sizeUniform: [UInt32] = [UInt32(w), UInt32(h), UInt32(pw), UInt32(ph), UInt32(scale)]
            encoder.setBytes(&sizeUniform, length: MemoryLayout<UInt32>.stride * sizeUniform.count, index: buffers.count)
            if includeBias {
                withUnsafeBytes(of: &biasUniform) { bytes in
                    encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: buffers.count + 1)
                }
            }
            encoder.dispatchThreads(
                MTLSize(width: fullRes ? w : pw, height: fullRes ? h : ph, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
            )
            encoder.endEncoding()
        }

        func finish(_ cb: any MTLCommandBuffer) throws {
            cb.commit()
            cb.waitUntilCompleted()
            if let error = cb.error { throw error }
        }

        var texA = try makeTexture()
        var texB = try makeTexture()
        let texOut = try makeTexture()
        var allTimesMS: [Double] = []
        allTimesMS.reserveCapacity(pairCount)

        for index in 0..<frames.count {
            try Task.checkCancellation()
            try autoreleasepool {
                let pb = frames[index]
                let start = CACurrentMediaTime()
                let cb = queue.makeCommandBuffer()!
                let image = CIImage(cvPixelBuffer: pb)
                let flipped = image.transformed(by: CGAffineTransform(
                    a: CGFloat(w) / image.extent.width, b: 0,
                    c: 0, d: -CGFloat(h) / image.extent.height,
                    tx: 0, ty: CGFloat(h)
                ))
                ciContext.render(
                    flipped, to: texB, commandBuffer: cb,
                    bounds: CGRect(x: 0, y: 0, width: w, height: h),
                    colorSpace: colorSpace
                )
                if index > 0 {
                    dispatch(cb, pipelineIndex: 0, textures: [texA, texB], buffers: [cand.buffer])
                }
                try finish(cb)

                if index > 0 {
                    try stage0.run()
                    let mid = queue.makeCommandBuffer()!
                    dispatch(
                        mid, pipelineIndex: 1, textures: [],
                        buffers: [cand.buffer, coarse.buffer, feat.buffer],
                        includeBias: true
                    )
                    try finish(mid)

                    try stage1.run()
                    let last = queue.makeCommandBuffer()!
                    dispatch(
                        last, pipelineIndex: 2, textures: [],
                        buffers: [feat.buffer, fine.buffer, field.buffer],
                        includeBias: true
                    )
                    dispatch(
                        last, pipelineIndex: 3, textures: [texA, texB, texOut],
                        buffers: [field.buffer], fullRes: true
                    )
                    try finish(last)

                    let elapsedMS = (CACurrentMediaTime() - start) * 1000.0
                    allTimesMS.append(elapsedMS)
                }
                swap(&texA, &texB)
            }
        }

        let measuredSamples = Array(allTimesMS.dropFirst(warmupPairs))
        let detail = "\(measuredSamples.count) adjacent moving-frame pairs after \(warmupPairs) warmups. Core ML FP16 (ANE) + Metal warp/compose from decoded NV12 to GPU RGB texture; zero CPU RGB packing or readback."
        return .measured(
            profile.id, profile.title,
            detail: detail,
            timing: "NV12 → GPU RGB wall",
            values: measuredSamples,
            budgetMS: budgetMS
        )
    }

    private static func makeBiasUniform(from safetensors: SafetensorsFile) throws -> FGBiasUniform {
        let d0 = try safetensors.slice(tensor: "block0.bot1.bias", byteOffset: 0, byteLength: 16)
        let d1 = try safetensors.slice(tensor: "block1.bot1.bias", byteOffset: 0, byteLength: 16)
        func load8(_ d: Data) -> (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16) {
            d.withUnsafeBytes { raw in
                (
                    raw.loadUnaligned(fromByteOffset: 0, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 2, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 6, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 8, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 10, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 12, as: UInt16.self),
                    raw.loadUnaligned(fromByteOffset: 14, as: UInt16.self)
                )
            }
        }
        return FGBiasUniform(b0: load8(d0), b1: load8(d1))
    }

    private static func ensureCompiledModel(
        stageIndex: Int,
        shapeLabel: String,
        templateRoot: URL,
        layout: CoreMLFGWeightLayout,
        safetensors: SafetensorsFile,
        cacheRoot: URL
    ) throws -> URL {
        let name = "block\(stageIndex)-\(shapeLabel)"
        let cachedURL = cacheRoot.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        try FileManager.default.createDirectory(
            at: cacheRoot, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let templateDir = templateRoot.appendingPathComponent(name, isDirectory: true)
        let manifestSrc = templateDir.appendingPathComponent("Manifest.json")
        let mlmodelSrc = templateDir.appendingPathComponent("model.mlmodel")
        guard FileManager.default.fileExists(atPath: manifestSrc.path),
              FileManager.default.fileExists(atPath: mlmodelSrc.path) else {
            throw RenderError.unavailable("Missing Core ML FG template \(name).")
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xframe-coreml-fg-\(UUID().uuidString)", isDirectory: true)
        let packageDir = stagingRoot.appendingPathComponent("\(name).mlpackage", isDirectory: true)
        let coreMLDir = packageDir.appendingPathComponent("Data/com.apple.CoreML", isDirectory: true)
        let weightsDir = coreMLDir.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        try FileManager.default.copyItem(at: manifestSrc, to: packageDir.appendingPathComponent("Manifest.json"))
        try FileManager.default.copyItem(at: mlmodelSrc, to: coreMLDir.appendingPathComponent("model.mlmodel"))
        let weightBin = try layout.buildWeightBin(stageIndex: stageIndex, from: safetensors)
        try weightBin.write(to: weightsDir.appendingPathComponent("weight.bin"), options: .atomic)

        let compiledTempURL = try MLModel.compileModel(at: packageDir)
        defer { try? FileManager.default.removeItem(at: compiledTempURL) }

        if !FileManager.default.fileExists(atPath: cachedURL.path) {
            do {
                try FileManager.default.moveItem(at: compiledTempURL, to: cachedURL)
            } catch {
                if !FileManager.default.fileExists(atPath: cachedURL.path) {
                    throw error
                }
            }
        }
        return cachedURL
    }
}
