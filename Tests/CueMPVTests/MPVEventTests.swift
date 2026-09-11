import CMpv
@testable import CueMPV
import Testing

@Suite struct MPVEventTests {
    @Test func describesStatusCodes() {
        #expect(MPVError.message(for: 0) == "success")
        #expect(MPVError.message(for: MPV_ERROR_LOADING_FAILED.rawValue) == "loading failed")
        #expect(MPVError(code: MPV_ERROR_OPTION_NOT_FOUND.rawValue, operation: "set option nope=1").description
            == "set option nope=1 failed: option not found")
    }

    @Test func copiesPropertyValues() {
        var flag: Int32 = 1
        var number: Int64 = 1080
        var seconds = 12.5
        #expect(MPVValue(format: MPV_FORMAT_FLAG, data: &flag) == .flag(true))
        #expect(MPVValue(format: MPV_FORMAT_INT64, data: &number) == .int64(1080))
        #expect(MPVValue(format: MPV_FORMAT_DOUBLE, data: &seconds) == .double(12.5))
        #expect(MPVValue(format: MPV_FORMAT_NONE, data: nil) == .none)
        "videotoolbox".withCString { text in
            var pointer: UnsafePointer<CChar>? = text
            #expect(MPVValue(format: MPV_FORMAT_STRING, data: &pointer) == .string("videotoolbox"))
        }
    }

    @Test func decodesEvents() {
        var none = mpv_event()
        none.event_id = MPV_EVENT_NONE
        #expect(MPVEvent(none) == nil)

        var reply = mpv_event()
        reply.event_id = MPV_EVENT_COMMAND_REPLY
        reply.reply_userdata = 42
        reply.error = MPV_ERROR_COMMAND.rawValue
        #expect(MPVEvent(reply) == .commandReply(id: 42, error: MPV_ERROR_COMMAND.rawValue))

        var seconds = 3.0
        "duration".withCString { name in
            withUnsafeMutablePointer(to: &seconds) { value in
                var property = mpv_event_property(name: name, format: MPV_FORMAT_DOUBLE, data: UnsafeMutableRawPointer(value))
                withUnsafeMutablePointer(to: &property) { propertyPointer in
                    var event = mpv_event()
                    event.event_id = MPV_EVENT_PROPERTY_CHANGE
                    event.data = UnsafeMutableRawPointer(propertyPointer)
                    #expect(MPVEvent(event) == .propertyChange(id: 0, name: "duration", value: .double(3)))
                }
            }
        }

        var endFile = mpv_event_end_file()
        endFile.reason = MPV_END_FILE_REASON_ERROR
        endFile.error = MPV_ERROR_LOADING_FAILED.rawValue
        withUnsafeMutablePointer(to: &endFile) { pointer in
            var event = mpv_event()
            event.event_id = MPV_EVENT_END_FILE
            event.data = UnsafeMutableRawPointer(pointer)
            #expect(MPVEvent(event) == .endFile(.error(code: MPV_ERROR_LOADING_FAILED.rawValue)))
        }
    }
}
