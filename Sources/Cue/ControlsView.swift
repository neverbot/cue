import AppKit
import CuePlayer

/// Minimal on-screen controls: play/pause, elapsed time, seek bar, duration, mute and volume.
final class ControlsView: NSVisualEffectView {
    var onCommand: ((PlayerCommand) -> Void)?

    private let playButton = ControlsView.button(symbol: "play.fill", label: "Play")
    private let muteButton = ControlsView.button(symbol: "speaker.wave.2.fill", label: "Mute")
    private let elapsedLabel = ControlsView.timeLabel()
    private let durationLabel = ControlsView.timeLabel()
    private let seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10

        playButton.target = self
        playButton.action = #selector(togglePause)
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        seekSlider.target = self
        seekSlider.action = #selector(seek(_:))
        seekSlider.isContinuous = false
        volumeSlider.target = self
        volumeSlider.action = #selector(changeVolume(_:))
        for slider in [seekSlider, volumeSlider] {
            slider.controlSize = .small
            slider.refusesFirstResponder = true
        }
        volumeSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let row = NSStackView(views: [playButton, elapsedLabel, seekSlider, durationLabel, muteButton, volumeSlider])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ playerState: PlayerState) {
        let playing = !playerState.isPaused && playerState.phase == .ready
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: playing ? "Pause" : "Play")
        muteButton.image = NSImage(
            systemSymbolName: playerState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            accessibilityDescription: playerState.isMuted ? "Unmute" : "Mute"
        )
        elapsedLabel.stringValue = PlaybackTime.format(playerState.position)
        durationLabel.stringValue = PlaybackTime.format(playerState.duration ?? 0)
        seekSlider.maxValue = max(playerState.duration ?? 0, 1)
        // Leave the knob alone while the user drags it.
        if seekSlider.cell?.isHighlighted != true {
            seekSlider.doubleValue = playerState.position
        }
        volumeSlider.doubleValue = playerState.volume
        let enabled = playerState.phase == .ready || playerState.phase == .ended
        for control in [playButton, muteButton, seekSlider, volumeSlider] as [NSControl] {
            control.isEnabled = enabled
        }
    }

    @objc private func togglePause() { onCommand?(.togglePause) }
    @objc private func toggleMute() { onCommand?(.toggleMute) }
    @objc private func seek(_ sender: NSSlider) { onCommand?(.seekAbsolute(seconds: sender.doubleValue)) }
    @objc private func changeVolume(_ sender: NSSlider) { onCommand?(.setVolume(sender.doubleValue)) }

    private static func button(symbol: String, label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.refusesFirstResponder = true
        button.contentTintColor = .white
        return button
    }

    private static func timeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        return label
    }
}
