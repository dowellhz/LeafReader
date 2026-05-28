import Cocoa

extension AppDelegate {
    @objc func showDiagnostics(_ sender: Any?) {
        if diagnosticsPanelController == nil {
            diagnosticsPanelController = DiagnosticsPanelController { [weak self] in
                DiagnosticsReport.rows(
                    updater: self?.updaterController?.updater,
                    controller: self?.controller
                )
            }
        }
        diagnosticsPanelController?.show(attachedTo: controller?.window)
    }
}
