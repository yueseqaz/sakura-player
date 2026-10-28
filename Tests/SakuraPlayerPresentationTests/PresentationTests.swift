import Combine
import Foundation
import SakuraPlayerCore
@testable import SakuraPlayerApp
import XCTest

final class PresentationTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testClockUpdatesDoNotInvalidateWindowModel() async {
        withModel { model in
            var windowEvents = 0
            var clockEvents = 0
            let windowSubscription = model.objectWillChange.sink { windowEvents += 1 }
            let clockSubscription = model.timeline.objectWillChange.sink { clockEvents += 1 }
            var state = PlaybackState()
            state.status = .paused
            state.duration = 100
            model.receiveEngineState(state)
            XCTAssertEqual(windowEvents, 1)
            for time in [1.0, 2.0, 3.0, 4.0] {
                state.currentTime = time
                model.receiveEngineState(state)
            }
            XCTAssertEqual(windowEvents, 1)
            XCTAssertEqual(clockEvents, 5)
            XCTAssertEqual(model.state.currentTime, 4)
            XCTAssertEqual(model.timeline.position.currentTime, 4)
            state.isMuted = true
            model.receiveEngineState(state)
            XCTAssertEqual(windowEvents, 2)
            withExtendedLifetime((windowSubscription, clockSubscription)) {}
        }
    }

    @MainActor
    func testDragPreviewIsLocalAndNotResetByBeginOrClockTick() async {
        withModel { model in
            var state = PlaybackState()
            state.status = .paused
            state.duration = 100
            state.currentTime = 10
            model.receiveEngineState(state)
            model.beginSeek()
            var windowEvents = 0
            let subscription = model.objectWillChange.sink { windowEvents += 1 }
            model.updatePendingSeek(42)
            model.beginSeek()
            XCTAssertEqual(model.timeline.position.displayedTime, 42)
            state.currentTime = 11
            model.receiveEngineState(state)
            XCTAssertEqual(model.timeline.position.displayedTime, 42)
            XCTAssertEqual(windowEvents, 0)
            model.updatePendingSeek(500)
            XCTAssertEqual(model.timeline.position.displayedTime, 100)
            model.commitSeek()
            XCTAssertNil(model.timeline.position.pendingTime)
            XCTAssertFalse(model.isSeeking)
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor
    func testCloseDiscardsDragPreview() async {
        withModel { model in
            model.beginSeek()
            model.updatePendingSeek(0.5)
            model.close()
            XCTAssertFalse(model.isSeeking)
            XCTAssertNil(model.timeline.position.pendingTime)
            XCTAssertEqual(model.state.status, .idle)
        }
    }

    @MainActor
    private func withModel(_ check: (PlayerViewModel) -> Void) {
        let suite = "SakuraPlayerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".json")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: historyURL)
        }
        let model = PlayerViewModel(defaults: defaults, history: PlaybackHistoryStore(fileURL: historyURL))
        check(model)
        model.close()
    }
}
