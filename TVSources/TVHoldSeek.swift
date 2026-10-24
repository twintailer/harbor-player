import SwiftUI

/// Observe remote button holds without replacing SwiftUI's normal focus navigation.
struct TVHoldSeek: UIViewRepresentable {
    var enabled: Bool
    var direction: (UIPress.PressType) -> Int?
    var begin: (Int) -> Void
    var advance: (Int, Double) -> Void
    var end: (Bool) -> Void

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.changedWindow = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateUIView(_ view: Host, context: Context) {
        context.coordinator.owner = self
        if !enabled {
            DispatchQueue.main.async { [weak coordinator = context.coordinator] in
                if coordinator?.owner.enabled == false { coordinator?.finish(cancelled: true) }
            }
        }
    }
    static func dismantleUIView(_ view: Host, coordinator: Coordinator) { coordinator.attach(nil) }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Host: UIView {
        var changedWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); changedWindow?(window) }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: TVHoldSeek
        private weak var window: UIWindow?
        private var gestures: [UILongPressGestureRecognizer] = []
        private var timer: Timer?
        private var activeDirection: Int?
        private weak var activeGesture: UILongPressGestureRecognizer?
        private var started = 0.0
        init(_ owner: TVHoldSeek) { self.owner = owner }
        func attach(_ window: UIWindow?) {
            guard self.window !== window else { return }
            finish(cancelled: true)
            for gesture in gestures { self.window?.removeGestureRecognizer(gesture) }
            gestures.removeAll(); self.window = window
            guard let window else { return }
            for type in [UIPress.PressType.leftArrow, .rightArrow, .select] {
                let gesture = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
                gesture.allowedPressTypes = [NSNumber(value: type.rawValue)]
                gesture.minimumPressDuration = 0.4
                gesture.delegate = self
                window.addGestureRecognizer(gesture); gestures.append(gesture)
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            owner.enabled && owner.direction(press.type) != nil
        }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard owner.enabled, let raw = gesture.allowedPressTypes.first?.intValue,
                      let type = UIPress.PressType(rawValue: raw), let direction = owner.direction(type) else { return }
                finish(cancelled: true)
                activeGesture = gesture; activeDirection = direction; started = ProcessInfo.processInfo.systemUptime
                owner.begin(direction)
                step()
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.step() }
                self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            case .ended: if activeGesture === gesture { finish(cancelled: false) }
            case .cancelled, .failed: if activeGesture === gesture { finish(cancelled: true) }
            default: break
            }
        }
        private func step() {
            guard owner.enabled, let direction = activeDirection else { finish(cancelled: true); return }
            owner.advance(direction, ProcessInfo.processInfo.systemUptime - started)
        }
        func finish(cancelled: Bool) {
            timer?.invalidate(); timer = nil
            guard activeDirection != nil else { return }
            activeDirection = nil; activeGesture = nil; owner.end(cancelled)
        }
    }
}
