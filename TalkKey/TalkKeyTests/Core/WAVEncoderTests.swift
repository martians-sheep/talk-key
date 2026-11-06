import XCTest
@testable import TalkKey

final class WAVEncoderTests: XCTestCase {

    private func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        data.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian
    }

    private func ascii(_ data: Data, _ offset: Int) -> String {
        String(decoding: data.subdata(in: offset..<offset + 4), as: UTF8.self)
    }

    func test_encode_writes16kMono16bitPCMHeader() {
        let data = WAVEncoder.encode(samples: [0, 1, -1], sampleRate: 16_000)

        XCTAssertEqual(ascii(data, 0), "RIFF")
        XCTAssertEqual(uint32(data, 4), UInt32(36 + 6))
        XCTAssertEqual(ascii(data, 8), "WAVE")
        XCTAssertEqual(ascii(data, 12), "fmt ")
        XCTAssertEqual(uint32(data, 16), 16)
        XCTAssertEqual(uint16(data, 20), 1, "PCM")
        XCTAssertEqual(uint16(data, 22), 1, "mono")
        XCTAssertEqual(uint32(data, 24), 16_000)
        XCTAssertEqual(uint32(data, 28), 32_000, "byte rate")
        XCTAssertEqual(uint16(data, 32), 2, "block align")
        XCTAssertEqual(uint16(data, 34), 16, "bits per sample")
        XCTAssertEqual(ascii(data, 36), "data")
        XCTAssertEqual(uint32(data, 40), 6)
    }

    func test_encode_writesSamplesLittleEndian() {
        let data = WAVEncoder.encode(samples: [1, -2], sampleRate: 16_000)

        XCTAssertEqual(data.count, 44 + 4)
        XCTAssertEqual(Array(data.suffix(4)), [0x01, 0x00, 0xFE, 0xFF])
    }
}
