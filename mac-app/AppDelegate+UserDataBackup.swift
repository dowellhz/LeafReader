import Cocoa
import UniformTypeIdentifiers

extension AppDelegate {
    func prepareUserDataBackupBeforePersistenceActivation() -> Bool {
        guard let configuration = UserDataBackupConfiguration.production() else {
            return true
        }
        let service = UserDataBackupService(configuration: configuration)
        userDataBackupService = service
        do {
            try service.recoverInterruptedRestoreIfNeeded()
            if let result = try service.performPendingRestoreIfNeeded() {
                restoredUserDataEntryCount = result.restoredEntryCount
            }
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = AppText.localized("无法安全恢复用户数据", "User data could not be recovered safely")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return false
        }
    }

    func showUserDataRestoreCompletionIfNeeded() {
        guard let restoredUserDataEntryCount else { return }
        self.restoredUserDataEntryCount = nil
        let alert = NSAlert()
        alert.messageText = AppText.localized("用户数据已恢复", "User data restored")
        alert.informativeText = AppText.localized(
            "已验证并恢复 \(restoredUserDataEntryCount) 个数据项。Keychain 中的 API 密钥未被更改。",
            "Validated and restored \(restoredUserDataEntryCount) data items. API keys in Keychain were not changed."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.localized("好", "OK"))
        alert.beginSheetModal(for: controller.window ?? NSWindow())
    }

    @objc func createUserDataBackup(_ sender: Any?) {
        guard let service = userDataBackupService else {
            showUserDataBackupError(UserDataBackupError.fileOperation("Application Support is unavailable"))
            return
        }
        let panel = NSSavePanel()
        panel.title = AppText.localized("备份用户数据", "Back Up User Data")
        panel.prompt = AppText.localized("备份", "Back Up")
        panel.nameFieldStringValue = defaultUserDataBackupName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(exportedAs: "com.linlu.leafreader.user-data-backup")]
        guard panel.runModal() == .OK, var destinationURL = panel.url else { return }
        if destinationURL.pathExtension.lowercased() != "leafreaderbackup" {
            destinationURL.appendPathExtension("leafreaderbackup")
        }

        controller.prepareForUserDataBackup()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let manifest = try service.createBackup(at: destinationURL)
                DispatchQueue.main.async {
                    self?.showUserDataBackupCompletion(
                        entryCount: manifest.entries.count,
                        destinationURL: destinationURL
                    )
                }
            } catch {
                DispatchQueue.main.async { self?.showUserDataBackupError(error) }
            }
        }
    }

    @objc func scheduleUserDataRestore(_ sender: Any?) {
        guard let service = userDataBackupService else {
            showUserDataBackupError(UserDataBackupError.fileOperation("Application Support is unavailable"))
            return
        }
        let panel = NSOpenPanel()
        panel.title = AppText.localized("恢复用户数据", "Restore User Data")
        panel.prompt = AppText.localized("验证", "Validate")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let backupURL = panel.url else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try service.scheduleRestore(at: backupURL)
                DispatchQueue.main.async {
                    self?.confirmScheduledUserDataRestore(service: service)
                }
            } catch {
                DispatchQueue.main.async { self?.showUserDataBackupError(error) }
            }
        }
    }

    private func confirmScheduledUserDataRestore(service: UserDataBackupService) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("备份已验证", "Backup validated")
        alert.informativeText = AppText.localized(
            "恢复将在下次启动时、数据库打开之前执行。Keychain 中的 API 密钥不会备份或覆盖。现在退出应用吗？",
            "Restore will run before databases open on the next launch. API keys in Keychain are neither backed up nor overwritten. Quit now?"
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("退出并准备恢复", "Quit and Prepare Restore"))
        alert.addButton(withTitle: AppText.localized("取消", "Cancel"))
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            do {
                try service.clearPendingRestore()
            } catch {
                showUserDataBackupError(error)
            }
            return
        }
        controller.prepareForUserDataBackup()
        NSApp.terminate(nil)
    }

    private func showUserDataBackupCompletion(entryCount: Int, destinationURL: URL) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("备份完成", "Backup complete")
        alert.informativeText = AppText.localized(
            "已备份 \(entryCount) 个数据项到：\n\(destinationURL.path)\n\nAPI 密钥未包含在备份中。",
            "Backed up \(entryCount) data items to:\n\(destinationURL.path)\n\nAPI keys were not included."
        )
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showUserDataBackupError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = AppText.localized("用户数据操作失败", "User data operation failed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func defaultUserDataBackupName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Leaf-Reader-Backup-\(formatter.string(from: Date())).leafreaderbackup"
    }
}
