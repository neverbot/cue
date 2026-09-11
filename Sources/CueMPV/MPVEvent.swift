import CMpv
import Foundation

/// Property formats Cue observes.
public enum MPVFormat: Sendable {
    case flag
    case int64
    case double
    case string

    var raw: mpv_format {
        switch self {
        case .flag: MPV_FORMAT_FLAG
        case .int64: MPV_FORMAT_INT64
        case .double: MPV_FORMAT_DOUBLE
        case .string: MPV_FORMAT_STRING
        }
    }
}

/// A property value copied out of libmpv's event memory.
public enum MPVValue: Equatable, Sendable {
    /// The property is unavailable (for example `duration` before a file is loaded).
    case none
    case flag(Bool)
    case int64(Int64)
    case double(Double)
    case string(String)

    init(format: mpv_format, data: UnsafeMutableRawPointer?) {
        guard let data else {
            self = .none
            return
        }
        switch format {
        case MPV_FORMAT_FLAG: self = .flag(data.load(as: Int32.self) != 0)
        case MPV_FORMAT_INT64: self = .int64(data.load(as: Int64.self))
        case MPV_FORMAT_DOUBLE: self = .double(data.load(as: Double.self))
        case MPV_FORMAT_STRING:
            if let pointer = data.load(as: UnsafePointer<CChar>?.self) {
                self = .string(String(cString: pointer))
            } else {
                self = .none
            }
        default: self = .none
        }
    }
}

public enum MPVEndFileReason: Equatable, Sendable {
    case endOfFile
    case stopped
    case quit
    case error(code: Int32)
    case redirect
    case unknown(UInt32)

    init(reason: mpv_end_file_reason, error: Int32) {
        switch reason {
        case MPV_END_FILE_REASON_EOF: self = .endOfFile
        case MPV_END_FILE_REASON_STOP: self = .stopped
        case MPV_END_FILE_REASON_QUIT: self = .quit
        case MPV_END_FILE_REASON_ERROR: self = .error(code: error)
        case MPV_END_FILE_REASON_REDIRECT: self = .redirect
        default: self = .unknown(reason.rawValue)
        }
    }
}

/// The libmpv events Cue reacts to, decoded into owned Swift values.
public enum MPVEvent: Equatable, Sendable {
    case shutdown
    case logMessage(prefix: String, level: String, text: String)
    case setPropertyReply(id: UInt64, error: Int32)
    case commandReply(id: UInt64, error: Int32)
    case fileLoaded
    case endFile(MPVEndFileReason)
    case videoReconfig
    case audioReconfig
    case seek
    case playbackRestart
    case propertyChange(id: UInt64, name: String, value: MPVValue)
    case other(UInt32)

    /// Returns nil for `MPV_EVENT_NONE`, which means the queue is empty.
    init?(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_NONE:
            return nil
        case MPV_EVENT_SHUTDOWN:
            self = .shutdown
        case MPV_EVENT_LOG_MESSAGE:
            let message = event.data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            self = .logMessage(
                prefix: String(cString: message.prefix),
                level: String(cString: message.level),
                text: String(cString: message.text).trimmingCharacters(in: .newlines)
            )
        case MPV_EVENT_SET_PROPERTY_REPLY:
            self = .setPropertyReply(id: event.reply_userdata, error: event.error)
        case MPV_EVENT_COMMAND_REPLY:
            self = .commandReply(id: event.reply_userdata, error: event.error)
        case MPV_EVENT_FILE_LOADED:
            self = .fileLoaded
        case MPV_EVENT_END_FILE:
            let endFile = event.data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            self = .endFile(MPVEndFileReason(reason: endFile.reason, error: endFile.error))
        case MPV_EVENT_VIDEO_RECONFIG:
            self = .videoReconfig
        case MPV_EVENT_AUDIO_RECONFIG:
            self = .audioReconfig
        case MPV_EVENT_SEEK:
            self = .seek
        case MPV_EVENT_PLAYBACK_RESTART:
            self = .playbackRestart
        case MPV_EVENT_PROPERTY_CHANGE:
            let property = event.data.assumingMemoryBound(to: mpv_event_property.self).pointee
            self = .propertyChange(
                id: event.reply_userdata,
                name: String(cString: property.name),
                value: MPVValue(format: property.format, data: property.data)
            )
        default:
            self = .other(event.event_id.rawValue)
        }
    }
}
