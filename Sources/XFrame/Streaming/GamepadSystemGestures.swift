import GameController

// Scoped to the focused playback input owner. Preserve each element's prior
// preference so disabling input, replacement and shutdown restore it exactly.
@MainActor
final class GamepadSystemGestures {
    private var saved: [(GCControllerElement, GCControllerElement.SystemGestureState)] = []

    func capture(_ elements: [GCControllerElement]) {
        for element in elements where !saved.contains(where: { $0.0 === element }) {
            saved.append((element, element.preferredSystemGestureState))
            element.preferredSystemGestureState = .disabled
        }
    }

    func restore() {
        for (element, preference) in saved { element.preferredSystemGestureState = preference }
        saved.removeAll()
    }
}
