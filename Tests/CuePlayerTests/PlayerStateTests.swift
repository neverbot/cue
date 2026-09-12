import CueMPV
@testable import CuePlayer
import Testing

@Suite struct PlayerStateTests {
    @Test func becomesReadyWhenPlaybackStarts() {
        var state = PlayerState()
        state.phase = .loading
        state.apply(.fileLoaded)
        #expect(state.phase == .loading)
        state.apply(.playbackRestarted)
        #expect(state.phase == .ready)
    }

    @Test func tracksPlaybackProperties() {
        var state = PlayerState()
        for event: EngineEvent in [.position(12.5), .duration(213), .paused(true), .buffering(true), .volume(55), .muted(true),
                                   .videoSize(VideoSize(width: 1280, height: 720))] {
            state.apply(event)
        }
        #expect(state.position == 12.5)
        #expect(state.duration == 213)
        #expect(state.isPaused && state.isBuffering && state.isMuted)
        #expect(state.volume == 55)
        #expect(state.videoSize == VideoSize(width: 1280, height: 720))
    }

    @Test func namesTheWindowAndFlagsSoftwareDecoding() {
        var state = PlayerState()
        #expect(state.windowTitle == "Cue")
        #expect(state.windowSubtitle == "")

        state.stream = TestStreams.stream()
        #expect(state.windowTitle == "Test stream dQw4w9WgXcQ")
        #expect(state.windowSubtitle == "")

        state.stream?.decoding = .software
        #expect(state.windowSubtitle == "Software decoding")
    }

    @Test func endsOrFailsButIgnoresStops() {
        var state = PlayerState()
        state.phase = .ready
        state.apply(.ended(.stopped))
        #expect(state.phase == .ready)
        state.apply(.ended(.finished))
        #expect(state.phase == .ended)
        state.apply(.playbackRestarted)
        #expect(state.phase == .ready)
        state.apply(.ended(.failed("loading failed")))
        #expect(state.phase == .failed("loading failed"))
    }
}

@Suite struct EngineEventMapperTests {
    @Test func mapsPlaybackEvents() {
        var mapper = EngineEventMapper()
        let events = mapper.map([
            .fileLoaded,
            .propertyChange(id: 0, name: "duration", value: .double(3)),
            .propertyChange(id: 0, name: "pause", value: .flag(false)),
            .playbackRestart,
            .propertyChange(id: 0, name: "time-pos", value: .double(0.5)),
            .propertyChange(id: 0, name: "eof-reached", value: .flag(false)),
            .propertyChange(id: 0, name: "eof-reached", value: .flag(true)),
            .logMessage(prefix: "cplayer", level: "warn", text: "ignored"),
        ])
        #expect(events == [.fileLoaded, .duration(3), .paused(false), .playbackRestarted, .position(0.5), .ended(.finished)])
    }

    @Test func emitsOneVideoSizePerBatchAfterBothDimensions() {
        var mapper = EngineEventMapper()
        let first = mapper.map([
            .propertyChange(id: 0, name: "video-params/dw", value: .int64(320)),
            .propertyChange(id: 0, name: "video-params/dh", value: .int64(180)),
        ])
        #expect(first == [.videoSize(VideoSize(width: 320, height: 180))])
        #expect(mapper.map([.propertyChange(id: 0, name: "video-params/dw", value: .int64(320))]) == [])
    }

    @Test func swapsDimensionsForQuarterTurns() {
        var mapper = EngineEventMapper()
        let events = mapper.map([
            .propertyChange(id: 0, name: "video-params/dw", value: .int64(1920)),
            .propertyChange(id: 0, name: "video-params/dh", value: .int64(1080)),
            .propertyChange(id: 0, name: "video-params/rotate", value: .int64(90)),
        ])
        #expect(events == [.videoSize(VideoSize(width: 1080, height: 1920))])
    }

    @Test func reportsTheSizeAgainForANewFile() {
        var mapper = EngineEventMapper()
        let dimensions: [MPVEvent] = [
            .propertyChange(id: 0, name: "video-params/dw", value: .int64(320)),
            .propertyChange(id: 0, name: "video-params/dh", value: .int64(180)),
        ]
        #expect(mapper.map(dimensions) == [.videoSize(VideoSize(width: 320, height: 180))])
        #expect(mapper.map([.fileLoaded]) == [.fileLoaded])
        #expect(mapper.map(dimensions) == [.videoSize(VideoSize(width: 320, height: 180))])
    }

    @Test func ignoresTeardownZeroSizes() {
        var mapper = EngineEventMapper()
        _ = mapper.map([
            .propertyChange(id: 0, name: "video-params/dw", value: .int64(320)),
            .propertyChange(id: 0, name: "video-params/dh", value: .int64(180)),
        ])
        #expect(mapper.map([.propertyChange(id: 0, name: "video-params/dw", value: .none)]) == [])
    }

    @Test func mapsEndOfFileReasons() {
        var mapper = EngineEventMapper()
        #expect(mapper.map([.endFile(.endOfFile)]) == [.ended(.finished)])
        #expect(mapper.map([.endFile(.stopped)]) == [.ended(.stopped)])
        #expect(mapper.map([.endFile(.error(code: -13))]) == [.ended(.failed(MPVError.message(for: -13)))])
    }
}
