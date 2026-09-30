import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    #if os(iOS)
    static var orientation: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientation }
    #endif
}

enum PlaybackOrientation {
    @MainActor static func setPlaying(_ playing: Bool, in scene: UIWindowScene? = nil) {
        #if os(iOS)
        let mask: UIInterfaceOrientationMask = playing ? .landscape : .portrait
        AppDelegate.orientation = mask
        guard let scene = scene ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            #if DEBUG
            print("Orientation request: \(error.localizedDescription)")
            #endif
        }
        #endif
    }
}
