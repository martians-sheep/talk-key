import XCTest
import AVFoundation
@testable import TalkKey

final class PCM16ResamplerTests: XCTestCase {

    func test_finish_with48kMonoOneSecond_returnsAbout16000Samples() {
        let resampler = PCM16Resampler()

        for buffer in TestAudioBuffers.chunks(sampleRate: 48_000, duration: 1.0) {
            resampler.append(buffer)
        }
        let samples = resampler.finish()

        XCTAssertEqual(Double(samples.count), 16_000, accuracy: 160)
    }

    func test_finish_with44kStereo_downmixesAndResamples() {
        let resampler = PCM16Resampler()

        resampler.append(TestAudioBuffers.sine(sampleRate: 44_100, channels: 2, duration: 0.5))
        let samples = resampler.finish()

        XCTAssertEqual(Double(samples.count), 8_000, accuracy: 160)
    }

    func test_finish_convertsAmplitudeToInt16Range() {
        let resampler = PCM16Resampler()

        resampler.append(TestAudioBuffers.sine(duration: 0.2, amplitude: 0.5))
        let samples = resampler.finish()

        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 12_000)
        XCTAssertLessThan(peak, 20_000)
    }

    func test_finish_withoutInput_returnsEmpty() {
        let resampler = PCM16Resampler()

        XCTAssertTrue(resampler.finish().isEmpty)
    }

    func test_reset_discardsPreviousSamples() {
        let resampler = PCM16Resampler()
        resampler.append(TestAudioBuffers.sine(duration: 0.5))

        resampler.reset()
        resampler.append(TestAudioBuffers.sine(duration: 0.25))
        let samples = resampler.finish()

        XCTAssertEqual(Double(samples.count), 4_000, accuracy: 160)
    }
}
