import Foundation
import LocalAuthentication

@MainActor protocol DeviceAuthenticating: AnyObject {
    func authenticate() async throws -> Bool
    func cancel()
}

@MainActor final class DeviceAuthentication: DeviceAuthenticating {
    private var context: LAContext?
    func authenticate() async throws -> Bool {
        cancel()
        // init() — inherited NSObject initializer.
        // https://developer.apple.com/documentation/objectivec/nsobject-swift.class/init()
        let current = LAContext()
        // var touchIDAuthenticationAllowableReuseDuration: TimeInterval { get set }
        // https://developer.apple.com/documentation/localauthentication/lacontext/touchidauthenticationallowablereuseduration
        current.touchIDAuthenticationAllowableReuseDuration = 0
        context = current
        defer { if context === current { context = nil } }
        // func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
        // https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:)
        return try await current.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to continue.")
    }
    func cancel() {
        // func invalidate()
        // https://developer.apple.com/documentation/localauthentication/lacontext/invalidate()
        context?.invalidate()
        context = nil
    }
}
