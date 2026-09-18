import SwiftUI
import Photos
import AVFoundation

enum Route: Equatable { case decoyLock, notes, landing, gate1, setup, gate2, vault }

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var route: Route = .decoyLock
    @Published private(set) var media: [MediaInfo] = []
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var importedAsset: PHAsset?
    @Published var askToDeleteOriginal = false
    @Published var photos: [PHAsset] = []
    @Published var photosAuthorized = false
    @Published var showingLibrary = false
    @Published var showingSettings = false
    @Published var exportCandidate: MediaInfo?
    let preview = MediaPreview()
    let notes = NotesStore()
    private let auth: DeviceAuthenticating
    private let credentials: Credentials
    private let store: MediaStore?
    private var lease: SessionLease?
    private var master: SecretBytes?
    private var gate1Succeeded = false
    private var generation: UInt64 = 0
    private let importer = PhotosImporter()
    private var pendingExportNotice: String?
    private var isAuthenticating = false

    init(auth: DeviceAuthenticating? = nil, store: MediaStore? = nil, credentials: Credentials? = nil) {
        self.auth = auth ?? DeviceAuthentication()
        let storage = store ?? (try? MediaStore())
        self.store = storage
        self.credentials = credentials ?? Credentials(hasMedia: {
            guard let storage else { throw VaultError.storage }
            return try storage.containsFiles()
        })
    }
    func unlockDecoy(_ input: String) -> Bool {
        guard route == .decoyLock else { return false }
        // This public, predetermined UI code is NOT a vault passcode or crypto gate.
        guard input == "7002" else { return false }
        route = .notes
        return true
    }
    func reveal() {
        guard route == .notes else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { route = .landing }
    }
    func enter() async {
        guard route == .landing, !busy else { return }
        message = nil; busy = true
        let ticket = generation
        let current = SessionLease()
        lease = current
        route = .gate1
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            guard try await auth.authenticate() else { throw VaultError.locked }
            guard ticket == generation, route == .gate1, lease === current else { return }
            try current.check()
            gate1Succeeded = true
            let existing = try await credentials.exists(lease: current)
            guard ticket == generation, gate1Succeeded, route == .gate1 else { return }
            route = existing ? .gate2 : .setup
            busy = false
        } catch {
            guard ticket == generation else { return }
            current.revoke(); lease = nil; gate1Succeeded = false
            route = .landing; busy = false
            message = "Authentication did not complete. Press Enter to try again."
        }
    }
    func submit(password: String, confirmation: String) async {
        guard gate1Succeeded, !busy, route == .gate2 || route == .setup, let lease else { return }
        let setup = route == .setup
        let ticket = generation
        message = nil
        do {
            if setup { try PasswordHash.validate(password) }
            guard !password.isEmpty, password.utf8.count <= 1024 else { throw VaultError.invalidPassword }
            let p = try lease.own(SecretBytes(password: password))
            let c = try lease.own(SecretBytes(password: confirmation))
            defer { p.destroy(); c.destroy() }
            busy = true
            let key: SecretBytes
            if setup { key = try await credentials.create(password: p, confirmation: c, lease: lease) }
            else { key = try await credentials.unlock(password: p, lease: lease) }
            guard ticket == generation, gate1Succeeded, self.lease === lease else { key.destroy(); return }
            try lease.check()
            master = key; route = .vault; busy = false
            await refresh()
            if ticket == generation, let notice = pendingExportNotice {
                message = notice; pendingExportNotice = nil
            }
        } catch {
            guard ticket == generation else { return }
            busy = false; message = error.localizedDescription
            // Setup may have persisted its verifier before a later step failed.
            if setup, (try? await credentials.exists(lease: lease)) == true,
               ticket == generation, gate1Succeeded { route = .gate2 }
        }
    }
    func changePasscode(old: String, new: String, confirmation: String) async {
        guard route == .vault, gate1Succeeded, !busy, let lease else { return }
        let ticket = generation
        do {
            try PasswordHash.validate(new)
            guard !old.isEmpty, old.utf8.count <= 1024 else { throw VaultError.invalidPassword }
            let p = try lease.own(SecretBytes(password: old))
            let n = try lease.own(SecretBytes(password: new))
            let c = try lease.own(SecretBytes(password: confirmation))
            defer { p.destroy(); n.destroy(); c.destroy() }
            busy = true
            try await credentials.change(old: p, new: n, confirmation: c, lease: lease)
            guard generation == ticket else { return }
            busy = false; showingSettings = false; message = "Passcode changed."
        } catch {
            guard generation == ticket else { return }
            busy = false; message = error.localizedDescription
        }
    }
    /// Called synchronously after the native privacy cover has been installed.
    func lock() {
        guard !isAuthenticating else { return }
        generation &+= 1
        route = .decoyLock
        gate1Succeeded = false
        busy = false
        auth.cancel()
        // Revoke permission to decrypt BEFORE waiting for renderer/import teardown.
        lease?.revoke(); lease = nil
        preview.clear()
        media.removeAll(); photos.removeAll()
        importedAsset = nil
        askToDeleteOriginal = false
        showingLibrary = false; showingSettings = false
        exportCandidate = nil
        message = nil
        importer.cancel()
        master?.destroy(); master = nil
    }
    func refresh() async {
        guard route == .vault, let master, let lease, let store else { return }
        let ticket = generation
        do {
            let result = try await Task.detached { try store.list(master: master, lease: lease) }.value
            guard ticket == generation, route == .vault else { return }
            media = result
        } catch { if ticket == generation { message = error.localizedDescription } }
    }
    func show(_ item: MediaInfo) async {
        guard route == .vault, let master, let lease, let store else { return }
        do { try await preview.open(item, store: store, master: master, lease: lease) }
        catch { if route == .vault { message = error.localizedDescription } }
    }
    func deleteMedia(_ item: MediaInfo) async {
        guard route == .vault, let lease, let store, !busy else { return }
        do { try store.remove(item.id, lease: lease); await refresh() }
        catch { message = error.localizedDescription }
    }
    func openLibrary() async {
        guard route == .vault, !busy else { return }
        let ticket = generation
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard ticket == generation, route == .vault else { return }
        photosAuthorized = status == .authorized || status == .limited
        guard photosAuthorized else { message = "Allow Photos access in Settings to import local photos and videos."; return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        photos = assets; showingLibrary = true
    }
    func importAsset(_ asset: PHAsset) async {
        guard route == .vault, !busy, let master, let lease, let store else { return }
        let ticket = generation
        showingLibrary = false; busy = true; message = nil; importedAsset = nil
        do {
            try await importer.run(asset: asset, store: store, master: master, lease: lease)
            guard ticket == generation, route == .vault else { return }
            importedAsset = asset // Issued only after EVERY resource has been verified.
            askToDeleteOriginal = true
            busy = false
            await refresh()
        } catch {
            guard ticket == generation else { return }
            busy = false; message = error.localizedDescription
            await refresh()
        }
    }
    func deleteOriginal() async {
        guard route == .vault, !busy, let asset = importedAsset, let lease else { return }
        let ticket = generation
        importedAsset = nil; askToDeleteOriginal = false
        do {
            try lease.check()
            // User has explicitly chosen Delete in the in-app confirmation dialog.
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
            if ticket == generation { importedAsset = nil; message = "Photos deletion requested. The originals may remain in Recently Deleted for up to 30 days." }
        } catch { if ticket == generation { message = "Photos did not delete the originals." } }
    }
    func requestExport(_ item: MediaInfo) {
        guard route == .vault, gate1Succeeded, !busy,
              UIApplication.shared.applicationState == .active else { return }
        exportCandidate = item
    }
    func confirmExport() async {
        guard route == .vault, gate1Succeeded, !busy,
              UIApplication.shared.applicationState == .active,
              let item = exportCandidate, let lease, let master, let store else { return }
        exportCandidate = nil
        let ticket = generation
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if readStatus != .authorized && readStatus != .limited && addStatus != .authorized {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard ticket == generation, route == .vault else { return }
            guard permission == .authorized || permission == .limited else {
                message = "Allow Photos access in Settings to export."; return
            }
        }
        // No extra Gate 2 prompt: the user explicitly approved using this live session.
        do {
            try lease.check()
            busy = true
            let outcome = try await PhotosExporter.run(item: item, store: store, master: master, lease: lease)
            let notice: String
            switch outcome.cleanup {
            case .removalFailed:
                notice = "The temporary export file could not be removed. An unencrypted temporary copy may remain on this device. The encrypted vault copy is unchanged."
            case .removedWithoutOverwrite:
                notice = "The temporary file was deleted, but its overwrite pass failed. Physical secure erasure is not guaranteed. The encrypted vault copy is unchanged."
            case .removed:
                notice = outcome.exported ? "Saved to Photos. That copy is outside DUMP’s protection. Your encrypted vault copy is unchanged." : "Export did not complete. The temporary file was removed; your encrypted vault copy is unchanged."
            }
            if ticket == generation { busy = false; message = notice }
            else { pendingExportNotice = notice } // Show only after a later successful unlock.
        } catch {
            if ticket == generation { busy = false; message = "Export could not start. Your encrypted vault copy is unchanged." }
        }
    }
}
