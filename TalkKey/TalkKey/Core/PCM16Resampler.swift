import AVFoundation

/// マイクのバッファを whisper 向けの 16kHz mono Int16 に逐次変換してためる。
/// 離した瞬間に変換し始めると待ち時間が延びるため、録音中に少しずつ変換しておく
final class PCM16Resampler {
    static let targetSampleRate: Double = 16_000

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: PCM16Resampler.targetSampleRate,
        channels: 1,
        interleaved: true
    )!
    private var converter: AVAudioConverter?
    private var samples: [Int16] = []

    var sampleCount: Int { samples.count }

    func reset() {
        converter = nil
        samples.removeAll(keepingCapacity: true)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, let converter = converter(for: buffer.format) else { return }
        var isConsumed = false
        convert(using: converter, inputFrames: buffer.frameLength, sourceRate: buffer.format.sampleRate) { _, status in
            if isConsumed {
                status.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return buffer
        }
    }

    /// 変換器に残っているぶんを吐き出して、ためた全サンプルを返す
    func finish() -> [Int16] {
        if let converter {
            let inputFormat = converter.inputFormat
            convert(using: converter, inputFrames: 0, sourceRate: inputFormat.sampleRate) { _, status in
                status.pointee = .endOfStream
                return nil
            }
        }
        converter = nil
        return samples
    }

    private func converter(for format: AVAudioFormat) -> AVAudioConverter? {
        if let converter, converter.inputFormat == format {
            return converter
        }
        // 入力デバイスが変わって形式が変わったら、それまでの分は確定させて作り直す
        if converter != nil {
            _ = finish()
        }
        let newConverter = AVAudioConverter(from: format, to: outputFormat)
        newConverter?.downmix = true
        converter = newConverter
        return newConverter
    }

    private func convert(
        using converter: AVAudioConverter,
        inputFrames: AVAudioFrameCount,
        sourceRate: Double,
        inputBlock: @escaping AVAudioConverterInputBlock
    ) {
        let ratio = Self.targetSampleRate / sourceRate
        let capacity = AVAudioFrameCount(Double(inputFrames) * ratio) + 1024
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: inputBlock)
            if output.frameLength > 0, let channel = output.int16ChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            // 出力が一杯で止まったときだけ続きを取りに行く
            guard status == .haveData, output.frameLength == output.frameCapacity else { return }
        }
    }
}
