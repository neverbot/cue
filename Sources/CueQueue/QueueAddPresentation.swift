import CueCore
import Foundation

/// What became of a video someone typed or pasted in.
public enum QueueAddOutcome: Equatable, Sendable {
    /// It was not queued before, and now it is.
    case added
    /// It was already queued, so nothing changed.
    case alreadyQueued
    /// The text named no YouTube video at all.
    case notRecognised
}

/// The words the settings window uses when a video is added by hand. Kept here, beside the other presentation
/// helpers, so what the app says about a paste can be tested without a window.
///
/// None of these sentences repeats what was typed. `AddRequestError` does quote the text it rejected, because a
/// `cue://` link arriving from a browser is worth showing back; a line the owner pasted into their own queue is
/// their private watch list, and a settings window ends up in screenshots.
public enum QueueAddPresentation {
    /// The decision itself, kept apart from the store and the window: `videoID` is nil when the text named no video,
    /// and `wasAdded` is what the queue reported for a video it did recognise.
    public static func outcome(videoID: VideoID?, wasAdded: Bool) -> QueueAddOutcome {
        guard videoID != nil else { return .notRecognised }
        return wasAdded ? .added : .alreadyQueued
    }

    public static func message(for outcome: QueueAddOutcome) -> String {
        switch outcome {
        case .added: "Added to the queue."
        case .alreadyQueued: "That video is already in the queue."
        case .notRecognised: "That is not a YouTube video id or link."
        }
    }
}
