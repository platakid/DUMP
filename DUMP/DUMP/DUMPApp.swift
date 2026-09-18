import SwiftUI

@main
@MainActor
struct DUMPApp: App {
    @UIApplicationDelegateAdaptor(PrivacyDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onAppear {
                    delegate.model = model
                    delegate.refreshCapture()
                }
        }
    }
}

@MainActor
final class PrivacyDelegate: NSObject, UIApplicationDelegate {

    weak var model: AppModel?

    private var observers: [NSObjectProtocol] = []
    private let shieldTag = 70020715

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        /*
         SECURITY / FACE ID BEHAVIOR

         willDeactivate:
             Show the privacy shield immediately.
             DO NOT lock/cancel authentication here.

         didEnterBackground:
             This is a real background transition.
             Lock the vault and invalidate the session.

         This prevents Face ID/system UI transitions from cancelling
         their own LAContext while still protecting the app when it
         genuinely enters the background.
         */

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIScene.willDeactivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cover()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIScene.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cover()
                    self?.model?.lock()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshCapture()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshCapture()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.showScreenshotNotice()
                }
            }
        )

        return true
    }

    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    // MARK: - Privacy Shield

    private func cover() {
        for window in windows where window.viewWithTag(shieldTag) == nil {

            let shield = UIView(frame: window.bounds)

            shield.tag = shieldTag
            shield.backgroundColor = .systemBackground
            shield.autoresizingMask = [
                .flexibleWidth,
                .flexibleHeight
            ]
            shield.isUserInteractionEnabled = true

            let label = UILabel()

            label.text = "DUMP"
            label.font = .systemFont(
                ofSize: 28,
                weight: .semibold
            )

            label.translatesAutoresizingMaskIntoConstraints = false

            shield.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(
                    equalTo: shield.centerXAnchor
                ),
                label.centerYAnchor.constraint(
                    equalTo: shield.centerYAnchor
                )
            ])

            window.addSubview(shield)
        }

        CATransaction.flush()
    }

    private func uncover() {
        windows.forEach {
            $0.viewWithTag(shieldTag)?
                .removeFromSuperview()
        }
    }

    // MARK: - Screenshot Notice

    private func showScreenshotNotice() {

        guard UIApplication.shared.applicationState == .active,
              !UIScreen.screens.contains(where: \.isCaptured),
              let window = windows.first(where: \.isKeyWindow)
        else {
            return
        }

        let notice = UILabel()

        notice.text =
            "Screenshot detected. iOS has already captured this screen."

        notice.numberOfLines = 0
        notice.textAlignment = .center

        notice.font =
            .preferredFont(forTextStyle: .footnote)

        notice.backgroundColor =
            .secondarySystemBackground

        notice.layer.cornerRadius = 14
        notice.clipsToBounds = true

        notice.translatesAutoresizingMaskIntoConstraints = false

        window.addSubview(notice)

        NSLayoutConstraint.activate([
            notice.leadingAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),

            notice.trailingAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),

            notice.topAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),

            notice.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 64
            )
        ])

        UIAccessibility.post(
            notification: .announcement,
            argument: notice.text
        )

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 6
        ) {
            notice.removeFromSuperview()
        }
    }

    // MARK: - UIApplication Lifecycle

    func applicationWillResignActive(
        _ application: UIApplication
    ) {
        /*
         IMPORTANT:

         Only install the privacy shield here.

         Do NOT call model.lock().

         Face ID and other system authentication UI can cause
         temporary inactivity. Cancelling LAContext here can prevent
         Face ID from ever beginning its scan.
         */
        cover()
    }

    func applicationDidEnterBackground(
        _ application: UIApplication
    ) {
        /*
         This is an actual background transition.

         Now invalidate the security session.
         */
        cover()
        model?.lock()
    }

    func applicationDidBecomeActive(
        _ application: UIApplication
    ) {
        refreshCapture()
    }

    // MARK: - Screen Capture

    func refreshCapture() {

        if UIScreen.screens.contains(where: \.isCaptured) {

            /*
             Active screen recording/capture is treated as a real
             security lock.
             */
            cover()
            model?.lock()

        } else if UIApplication.shared.applicationState == .active {

            uncover()
        }
    }
}
