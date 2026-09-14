import CuePlayer
import Testing

@Suite struct SubtitleLiftTests {
    @Test func restsWhereTheUserPutItWhileTheControlsAreHidden() {
        #expect(SubtitleLift.position(baseline: 100, occludedHeight: 0, pictureHeight: 400) == 100)
    }

    @Test func raisesTheSubtitlesClearOfTheControls() {
        // 100 points of a 400-point picture is a quarter of its height, and `sub-pos` is a percentage of that height,
        // so a quarter of the picture is 25 of its units.
        #expect(SubtitleLift.position(baseline: 100, occludedHeight: 100, pictureHeight: 400) == 75)
    }

    @Test func liftsRelativeToWhateverBaselineTheUserChose() {
        // The lift is applied to their setting, never in place of it: a custom resting position is still where the
        // subtitles return to, and still what the raised position is measured down from.
        #expect(SubtitleLift.position(baseline: 80, occludedHeight: 100, pictureHeight: 400) == 55)
        #expect(SubtitleLift.position(baseline: 80, occludedHeight: 0, pictureHeight: 400) == 80)
    }

    @Test func staysInsideTheRangeMpvAccepts() {
        // A bar taller than the picture would otherwise ask for a negative position, which mpv refuses outright.
        #expect(SubtitleLift.position(baseline: 100, occludedHeight: 2000, pictureHeight: 400) == SubtitleLift.range.lowerBound)
        // And a baseline from outside the range cannot smuggle itself through either.
        #expect(SubtitleLift.position(baseline: 400, occludedHeight: 0, pictureHeight: 400) == SubtitleLift.range.upperBound)
    }

    @Test func leavesThePositionAloneWhenThePictureCannotBeMeasured() {
        // A window that has not laid out yet reports no height; a lift computed from it would move the subtitles for
        // no reason at all.
        #expect(SubtitleLift.position(baseline: 100, occludedHeight: 100, pictureHeight: 0) == 100)
    }

    @Test func sendsThePositionAsTheSameMpvPropertyTheStyleUses() {
        #expect(SubtitleLift.positionProperty == "sub-pos")
        #expect(
            SubtitleLift.command(baseline: 100, occludedHeight: 100, pictureHeight: 400).mpvArguments
                == ["set", "sub-pos", "75"]
        )
    }
}
