import Testing
@testable import StashKit

@Suite struct StashActivityTests {
    /// `seconds` ticks of one second each, playing forward at `speed` from `from`.
    private func play(_ activity: inout StashActivity, from: Double, seconds: Int, speed: Double = 1) -> [StashActivityRequest] {
        (1...seconds).flatMap { i in
            activity.tick(position: from + Double(i) * speed, elapsed: 1, playingForward: true, speed: speed)
        }
    }

    @Test func countsForwardPlay() {
        var activity = StashActivity(duration: 100, minimumPlayPercent: 50, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        #expect(play(&activity, from: 0, seconds: 10) == [.save(resumeTime: 10, playDuration: 10)])
    }

    @Test func jumpsDuringPlaybackDoNotCount() {
        var activity = StashActivity(duration: 1000, minimumPlayPercent: 50, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = activity.tick(position: 1, elapsed: 1, playingForward: true, speed: 1)
        _ = activity.tick(position: 61, elapsed: 1, playingForward: true, speed: 1)   // ↑: seek 60 s while playing
        _ = activity.tick(position: 62, elapsed: 1, playingForward: true, speed: 1)
        #expect(activity.flush(position: 62) == [.save(resumeTime: 62, playDuration: 2)])
    }

    @Test func loopBackDoesNotCount() {
        var activity = StashActivity(duration: 1000, minimumPlayPercent: 50, enabled: true)
        _ = activity.tick(position: 100, elapsed: 0, playingForward: true, speed: 1)
        _ = activity.tick(position: 101, elapsed: 1, playingForward: true, speed: 1)
        _ = activity.tick(position: 20, elapsed: 1, playingForward: true, speed: 1)   // A-B loop back to A
        _ = activity.tick(position: 21, elapsed: 1, playingForward: true, speed: 1)
        #expect(activity.flush(position: 21) == [.save(resumeTime: 21, playDuration: 2)])
    }

    @Test func slowAndReverseDoNotCount() {
        var activity = StashActivity(duration: 1000, minimumPlayPercent: 50, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = activity.tick(position: 0.5, elapsed: 1, playingForward: true, speed: 0.5)
        _ = activity.tick(position: -0.5, elapsed: 1, playingForward: false, speed: 1)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 2)
        _ = activity.tick(position: 2, elapsed: 1, playingForward: true, speed: 2)
        #expect(activity.flush(position: 2) == [.save(resumeTime: 2, playDuration: 2)])
    }

    @Test func resumeResetsNearTheEnd() {
        var nearEnd = StashActivity(duration: 100, minimumPlayPercent: 100, enabled: true)
        _ = nearEnd.tick(position: 97, elapsed: 0, playingForward: true, speed: 1)
        _ = nearEnd.tick(position: 98, elapsed: 1, playingForward: true, speed: 1)
        #expect(nearEnd.flush(position: 98) == [.save(resumeTime: 0, playDuration: 1)])
        var before = StashActivity(duration: 100, minimumPlayPercent: 100, enabled: true)
        _ = before.tick(position: 96.9, elapsed: 0, playingForward: true, speed: 1)
        _ = before.tick(position: 97.9, elapsed: 1, playingForward: true, speed: 1)
        #expect(before.flush(position: 97.9) == [.save(resumeTime: 97.9, playDuration: 1)])
    }

    @Test func playCountedOnceAtThreshold() {
        var half = StashActivity(duration: 100, minimumPlayPercent: 50, enabled: true)
        _ = half.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        let sent = play(&half, from: 0, seconds: 70)
        #expect(sent.filter { $0 == .addPlay }.count == 1)
        #expect(sent.firstIndex(of: .addPlay) == sent.firstIndex(of: .save(resumeTime: 50, playDuration: 10))! + 1)
        #expect(!half.flush(position: 70).contains(.addPlay))
        var any = StashActivity(duration: 100, minimumPlayPercent: 0, enabled: true)
        _ = any.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = any.tick(position: 1, elapsed: 1, playingForward: true, speed: 1)
        #expect(any.flush(position: 1) == [.save(resumeTime: 1, playDuration: 1), .addPlay])
    }

    @Test func flushWithoutPlaySendsNothing() {
        var activity = StashActivity(duration: 100, minimumPlayPercent: 0, enabled: true)
        _ = activity.tick(position: 5, elapsed: 0, playingForward: false, speed: 1)
        _ = activity.tick(position: 5, elapsed: 1, playingForward: false, speed: 1)
        #expect(activity.flush(position: 5) == [])
    }

    @Test func failedSendIsCarried() {
        var activity = StashActivity(duration: 1000, minimumPlayPercent: 100, enabled: true)
        activity.failed(.save(resumeTime: 5, playDuration: 5))
        _ = activity.tick(position: 5, elapsed: 0, playingForward: true, speed: 1)
        _ = play(&activity, from: 5, seconds: 3)
        #expect(activity.flush(position: 8) == [.save(resumeTime: 8, playDuration: 8)])
    }

    @Test func failedPlayIsSentAgain() {
        var activity = StashActivity(duration: 100, minimumPlayPercent: 0, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = activity.tick(position: 1, elapsed: 1, playingForward: true, speed: 1)
        #expect(activity.flush(position: 1).contains(.addPlay))
        activity.failed(.addPlay)
        _ = activity.tick(position: 2, elapsed: 1, playingForward: true, speed: 1)
        #expect(activity.flush(position: 2) == [.save(resumeTime: 2, playDuration: 1), .addPlay])
    }

    @Test func disabledSendsNothing() {
        var activity = StashActivity(duration: 100, minimumPlayPercent: 0, enabled: false)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        #expect(play(&activity, from: 0, seconds: 20).isEmpty)
        #expect(activity.flush(position: 20).isEmpty)
    }

    @Test func settingsArrivingLateApplyToWhatWasCarried() {
        // Stash's UI settings were not known yet: everything was held back (failed) until they came.
        var activity = StashActivity(duration: 10, minimumPlayPercent: 0, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = play(&activity, from: 0, seconds: 3)
        for request in activity.flush(position: 3) { activity.failed(request) }
        activity.apply(minimumPlayPercent: 50, enabled: true)
        _ = play(&activity, from: 3, seconds: 1)
        #expect(activity.flush(position: 4) == [.save(resumeTime: 4, playDuration: 4)])   // 4 s < 50 % of 10 s: no play yet
        _ = play(&activity, from: 4, seconds: 1)
        #expect(activity.flush(position: 5) == [.save(resumeTime: 5, playDuration: 1), .addPlay])
    }

    @Test func trackingTurnedOffInStashDropsWhatWasHeld() {
        var activity = StashActivity(duration: 100, minimumPlayPercent: 0, enabled: true)
        _ = activity.tick(position: 0, elapsed: 0, playingForward: true, speed: 1)
        _ = play(&activity, from: 0, seconds: 3)
        for request in activity.flush(position: 3) { activity.failed(request) }
        activity.apply(minimumPlayPercent: 0, enabled: false)
        _ = play(&activity, from: 3, seconds: 12)
        #expect(activity.flush(position: 15).isEmpty)
    }
}
