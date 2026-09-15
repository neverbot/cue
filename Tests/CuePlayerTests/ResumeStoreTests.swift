@testable import CuePlayer
import Foundation
import Testing

@Suite struct ResumePolicyTests {
    let policy = ResumePolicy()

    @Test func keepsPositionsBetweenTheStartAndTheEnd() {
        #expect(!policy.isWorthKeeping(position: 9.9, duration: 213))
        #expect(policy.isWorthKeeping(position: 10, duration: 213))
        #expect(policy.isWorthKeeping(position: 192.9, duration: 213))
        #expect(!policy.isWorthKeeping(position: 193, duration: 213))
        #expect(policy.isWorthKeeping(position: 5000, duration: nil))
    }

    @Test func resumesOnlyWorthwhileEntries() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(policy.startPosition(for: ResumeEntry(position: 42, duration: 213, updatedAt: date)) == 42)
        #expect(policy.startPosition(for: ResumeEntry(position: 205, duration: 213, updatedAt: date)) == nil)
        #expect(policy.startPosition(for: nil) == nil)
    }
}
