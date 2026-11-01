import AppKit

@MainActor
final class CompanionDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), app = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); app.submenu = appMenu; menu.addItem(app)
        let edit = NSMenuItem(), editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c"); edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
        let arguments = CommandLine.arguments
        if let position = arguments.firstIndex(of: "--verify"), arguments.count > position + 1 {
            if arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            let controller = PreviewController(extensionMode: true)
            let window = NSWindow(contentViewController: controller); window.setContentSize(NSSize(width: 1000, height: 740)); window.center(); window.makeKeyAndOrderFront(nil); windows.append(window)
            Task {
                do {
                    let output = URL(fileURLWithPath: arguments[position + 1])
                    let checks = try await controller.verify(demo: Bundle.main.resourceURL!.appendingPathComponent("Demo"), output: output)
                    print("PASS: \(checks.count) native checks")
                    NSApp.terminate(nil)
                } catch { fputs("Verification failed: \(error)\n", stderr); exit(1) }
            }
            return
        }
        showSetup()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func showSetup() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Folder Preview Droplet"
        let icon = NSImageView(image: NSWorkspace.shared.icon(for: .folder)); icon.imageScaling = .scaleProportionallyUpOrDown; icon.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let title = NSTextField(labelWithString: "L’aperçu des dossiers dans le Finder"); title.font = .systemFont(ofSize: 19, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "Activez Folder Preview Droplet dans les extensions Coup d’œil de macOS. Sélectionnez ensuite un dossier dans le Finder, puis appuyez sur Espace ou ⌘Y.\n\nPrésentation, miniatures et colonnes se règlent depuis le menu ⚙︎ en bas de l’aperçu.")
        description.textColor = .secondaryLabelColor
        let settings = NSButton(title: "Ouvrir les Réglages Système…", target: self, action: #selector(openSettings))
        let demo = NSButton(title: "Afficher le dossier de démonstration", target: self, action: #selector(showDemo))
        let stack = NSStackView(views: [icon, title, description, settings, demo]); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -30), stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)])
        windows.append(window); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    @objc private func showDemo() { if let url = Bundle.main.resourceURL?.appendingPathComponent("Demo") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}
@main
struct CompanionMain {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = CompanionDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run(); withExtendedLifetime(delegate) {}
    }
}
