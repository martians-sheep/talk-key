import Foundation

enum WAVEncoder {
    private static let headerSize = 44
    private static let bitsPerSample: UInt16 = 16
    private static let channels: UInt16 = 1

    /// mono 16bit PCM の WAV を作る
    static func encode(samples: [Int16], sampleRate: Int) -> Data {
        let bytesPerSample = Int(bitsPerSample / 8)
        let dataSize = UInt32(samples.count * bytesPerSample)
        var data = Data(capacity: headerSize + Int(dataSize))

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(channels, to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * Int(channels) * bytesPerSample), to: &data)
        append(channels * UInt16(bytesPerSample), to: &data)
        append(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize, to: &data)
        samples.withUnsafeBufferPointer { pointer in
            if Int16(littleEndian: 1) == 1 {
                data.append(UnsafeBufferPointer(start: UnsafeRawPointer(pointer.baseAddress)?.assumingMemoryBound(to: UInt8.self), count: pointer.count * bytesPerSample))
            } else {
                for sample in pointer { append(UInt16(bitPattern: sample), to: &data) }
            }
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
