import AVFoundation
import Testing
@testable import DzhmilCore

@Suite struct AudioBlocksTests {
    func sine(frames: AVAudioFrameCount, rate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = sin(Float(i) * 0.05) * 0.5 }
        return buffer
    }

    @Test func tapBlockResamplesOffMainThread() async throws {
        let input = sine(frames: 4800, rate: 48_000)
        let sink = AudioCapture.Sink()
        let block = try AudioCapture.tapBlock(inputFormat: input.format, sink: sink)
        nonisolated(unsafe) let buffer = input
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                for i in 0..<3 { block(buffer, AVAudioTime(sampleTime: AVAudioFramePosition(i * 4800), atRate: 48_000)) }
                c.resume()
            }
        }
        let samples = sink.take()
        #expect(abs(samples.count - 4800) <= 300)
        #expect(sink.take().isEmpty)
    }

    @Test func propellerRenderBlockRunsOffMainThread() async {
        let synth = PropellerSynth()
        synth.setTarget(0.02)
        let block = synth.renderBlock(sampleRate: 48_000)
        let out = sine(frames: 512, rate: 48_000)
        nonisolated(unsafe) let buffer = out
        let status: OSStatus = await withCheckedContinuation { c in
            Thread.detachNewThread {
                var silence = ObjCBool(false)
                var time = AudioTimeStamp()
                c.resume(returning: block(&silence, &time, 512, buffer.mutableAudioBufferList))
            }
        }
        #expect(status == noErr)
    }

    func peak(_ synth: PropellerSynth, seconds: Double) -> Float {
        let rate = 48_000.0
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = sine(frames: frames, rate: rate)
        let block = synth.renderBlock(sampleRate: rate)
        var silence = ObjCBool(false)
        var time = AudioTimeStamp()
        _ = block(&silence, &time, frames, buffer.mutableAudioBufferList)
        let tail = Int(frames) - 4800
        return (tail..<Int(frames)).map { abs(buffer.floatChannelData![0][$0]) }.max() ?? 0
    }

    @Test func purrSoundsEvenWhenTheHumIsSilent() {
        let quiet = PropellerSynth()
        #expect(peak(quiet, seconds: 1) == 0)
        let purring = PropellerSynth()
        purring.setPurr(true)
        #expect(peak(purring, seconds: 1) > 0.005)
    }
}
