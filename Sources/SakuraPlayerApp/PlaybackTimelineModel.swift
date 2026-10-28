import Combine
import Foundation
import SakuraPlayerCore

@MainActor
final class PlaybackTimelineModel: ObservableObject {
    struct Position: Equatable {
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var pendingTime: TimeInterval?

        var displayedTime: TimeInterval { pendingTime ?? currentTime }
    }

    @Published private(set) var position = Position()

    func update(from state: PlaybackState) {
        var next = position
        next.currentTime = state.currentTime
        next.duration = state.duration
        if next != position { position = next }
    }

    func preview(_ time: TimeInterval?) {
        if position.pendingTime != time { position.pendingTime = time }
    }
}
