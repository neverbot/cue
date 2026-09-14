import AppKit
import CueCore
import CuePlayer

/// The on-screen controls: play/pause, elapsed time, the seek bar, duration, chapters, subtitles, the mini player,
/// mute and volume — on one translucent bar.
final class ControlsView: NSView {
    var onCommand: ((PlayerCommand) -> Void)?
    /// Forwarded from the seek bar, in this view's coordinates.
    var onHover: ((Double?, CGFloat) -> Void)?
    /// Full screen cannot resize the window, so the fit control is greyed there. The window says when it is in full
    /// screen; this view never goes looking for one of its own.
    var windowIsFullScreen = false {
        didSet { updateFitWindowButton() }
    }

    let seekBar = SeekBarView()

    /// Whether a video is loaded, remembered from the last `update(_:timeline:)` so the fit button can be re-enabled
    /// on leaving full screen without waiting for the next state change.
    private var isReady = false

    private let playButton = ControlsView.button(symbol: "play.fill", label: "Play")
    private let muteButton = ControlsView.button(symbol: "speaker.wave.2.fill", label: "Mute")
    private let chaptersButton = ControlsView.button(symbol: "list.bullet", label: "Chapters")
    private let subtitlesButton = ControlsView.button(symbol: "captions.bubble", label: "Subtitles")
    private let fitWindowButton = ControlsView.button(symbol: "aspectratio", label: "Fit Window to Video")
    private let miniButton = ControlsView.button(symbol: "rectangle.inset.bottomright.filled", label: "Mini Player")
    private let elapsedLabel = ControlsView.timeLabel()
    private let durationLabel = ControlsView.timeLabel()
    private let chapterLabel = ControlsView.chapterLabel()
    private let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        ChromeStyle.applyPanel(to: self, cornerRadius: ChromeStyle.controlsCornerRadius)
        ChromeStyle.applyShadow(to: self)

        playButton.target = self
        playButton.action = #selector(togglePause)
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        chaptersButton.target = self
        chaptersButton.action = #selector(toggleChapters)
        subtitlesButton.target = self
        subtitlesButton.action = #selector(toggleSubtitles)
        fitWindowButton.target = self
        fitWindowButton.action = #selector(fitWindowToVideo)
        miniButton.target = self
        miniButton.action = #selector(toggleMini)
        volumeSlider.target = self
        volumeSlider.action = #selector(changeVolume(_:))
        volumeSlider.controlSize = .small
        volumeSlider.refusesFirstResponder = true
        volumeSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        seekBar.onScrub = { [weak self] seconds, isFinal in
            guard isFinal else { return }
            self?.onCommand?(.seekAbsolute(seconds: seconds))
        }
        seekBar.onHover = { [weak self] seconds, x in
            guard let self else { return }
            self.onHover?(seconds, self.convert(NSPoint(x: x, y: 0), from: self.seekBar).x)
        }

        let times = NSStackView(views: [elapsedLabel, seekBar, durationLabel])
        times.orientation = .horizontal
        times.spacing = 8
        let buttons = NSStackView(views: [
            playButton, chapterLabel, NSView(), chaptersButton, subtitlesButton, fitWindowButton, miniButton,
            muteButton, volumeSlider,
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let column = NSStackView(views: [times, buttons])
        column.orientation = .vertical
        column.spacing = 2
        column.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `timeline` decides the ticks and the chapter name; this view decides nothing.
    func update(_ playerState: PlayerState, timeline: ChapterTimeline) {
        let playing = !playerState.isPaused && playerState.phase == .ready
        playButton.image = Self.symbol(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play")
        muteButton.image = Self.symbol(
            playerState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            label: playerState.isMuted ? "Unmute" : "Mute"
        )
        elapsedLabel.stringValue = PlaybackTime.format(playerState.position)
        durationLabel.stringValue = PlaybackTime.format(playerState.duration ?? 0)
        seekBar.duration = playerState.duration
        seekBar.position = playerState.position
        seekBar.chapterFractions = timeline.tickFractions
        chapterLabel.stringValue = timeline.chapter(at: playerState.position)?.title ?? ""
        chapterLabel.isHidden = timeline.isEmpty

        let enabled = playerState.phase == .ready || playerState.phase == .ended
        seekBar.isEnabled = enabled
        // Enabled with no chapters too, like the menu item: the inspector says the video has none, which beats a
        // button that refuses silently.
        chaptersButton.isEnabled = enabled
        subtitlesButton.isEnabled = enabled && !(playerState.stream?.captionTracks.isEmpty ?? true)
        miniButton.isEnabled = enabled
        isReady = enabled
        updateFitWindowButton()
        for control in [playButton, muteButton, volumeSlider] as [NSControl] {
            control.isEnabled = enabled
        }
        volumeSlider.doubleValue = playerState.volume
    }

    /// Marks the subtitles button when a track is showing, so the state is visible without opening the inspector.
    func setSubtitlesActive(_ active: Bool) {
        subtitlesButton.contentTintColor = active ? .controlAccentColor : .white
    }

    @objc private func togglePause() { onCommand?(.togglePause) }
    @objc private func toggleMute() { onCommand?(.toggleMute) }
    @objc private func toggleChapters() { onCommand?(.toggleChaptersInspector) }
    @objc private func toggleSubtitles() { onCommand?(.toggleSubtitlesInspector) }
    @objc private func toggleMini() { onCommand?(.toggleMiniPlayer) }
    @objc private func fitWindowToVideo() { onCommand?(.fitWindowToVideo) }
    @objc private func changeVolume(_ sender: NSSlider) { onCommand?(.setVolume(sender.doubleValue)) }

    private func updateFitWindowButton() {
        fitWindowButton.isEnabled = isReady && !windowIsFullScreen
    }

    private static func symbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
    }

    private static func button(symbol name: String, label: String) -> NSButton {
        let button = NSButton(image: symbol(name, label: label) ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.refusesFirstResponder = true
        button.contentTintColor = .white
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private static func timeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        return label
    }

    private static func chapterLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white.withAlphaComponent(0.75)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
