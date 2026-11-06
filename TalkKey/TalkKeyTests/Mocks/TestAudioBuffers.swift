import AVFoundation

enum TestAudioBuffers {
    /// 指定のサンプルレート・チャンネル数の Float32 サイン波バッファを作る
    static func sine(
        sampleRate: Double = 48_000,
        channels: AVAudioChannelCount = 1,
        duration: TimeInterval,
        frequency: Double = 440,
        amplitude: Float = 0.5
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                data[i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
            }
        }
        return buffer
    }

    /// duration 秒ぶんを chunk 秒ずつに分けたバッファ列（マイクのタップから届く形を模す）
    static func chunks(sampleRate: Double = 48_000, duration: TimeInterval, chunk: TimeInterval = 0.1) -> [AVAudioPCMBuffer] {
        let count = Int((duration / chunk).rounded())
        return (0..<count).map { _ in sine(sampleRate: sampleRate, duration: chunk) }
    }
}
