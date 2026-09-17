import SwiftUI

@main @MainActor struct DUMPApp: App {
    @UIApplicationDelegateAdaptor(PrivacyDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onAppear { delegate.model = model; delegate.refreshCapture() }
        }
    }
}

@MainActor final class PrivacyDelegate: NSObject, UIApplicationDelegate {
    weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private let shieldTag = 70020715
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // SwiftUI uses scenes. Observe native scene notifications as well as app callbacks
        // so the opaque cover does not depend on a later SwiftUI state/render pass.
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cover(); self?.model?.lock() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCapture() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCapture() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showScreenshotNotice() }
        })
        return true
    }
    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }
    private func cover() {
        for window in windows where window.viewWithTag(shieldTag) == nil {
            let shield = UIView(frame: window.bounds)
            shield.tag = shieldTag
            shield.backgroundColor = .systemBackground
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shield.isUserInteractionEnabled = true
            let label = UILabel()
            label.text = "DUMP"; label.font = .systemFont(ofSize: 28, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            shield.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: shield.centerXAnchor), label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)])
            window.addSubview(shield)
        }
        CATransaction.flush()
    }
    private func uncover() { windows.forEach { $0.viewWithTag(shieldTag)?.removeFromSuperview() } }
    private func showScreenshotNotice() {
        // A native window overlay is visible above SwiftUI sheets and video previews.
        guard UIApplication.shared.applicationState == .active,
              !UIScreen.screens.contains(where: \.isCaptured),
              let window = windows.first(where: \.isKeyWindow) else { return }
        let notice = UILabel()
        notice.text = "Screenshot detected. iOS has already captured this screen."
        notice.numberOfLines = 0
        notice.textAlignment = .center
        notice.font = .preferredFont(forTextStyle: .footnote)
        notice.backgroundColor = .secondarySystemBackground
        notice.layer.cornerRadius = 14; notice.clipsToBounds = true
        notice.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(notice)
        NSLayoutConstraint.activate([
            notice.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            notice.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            notice.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            notice.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        UIAccessibility.post(notification: .announcement, argument: notice.text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { notice.removeFromSuperview() }
    }
    func applicationWillResignActive(_ application: UIApplication) {
        cover() // Native opaque cover first, before SwiftUI rendering/session cleanup.
        model?.lock()
    }
    func applicationDidEnterBackground(_ application: UIApplication) {
        cover(); model?.lock()
    }
    func applicationDidBecomeActive(_ application: UIApplication) { refreshCapture() }
    func refreshCapture() {
        if UIScreen.screens.contains(where: \.isCaptured) {
            cover(); model?.lock()
        } else if UIApplication.shared.applicationState == .active { uncover() }
    }
}
