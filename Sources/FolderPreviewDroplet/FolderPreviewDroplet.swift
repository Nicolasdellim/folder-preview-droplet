import AppKit
import Combine
import SwiftUI
import DroppyKit

@objc(FolderPreviewDropletPrincipal)
public final class FolderPreviewDropletPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { FolderPreviewDroplet() }
}
@MainActor
public final class FolderPreviewDroplet: NSObject, ObservableObject, Droplet, SettingsPaneProviding {
    public nonisolated static let id: DropletID = "folder-preview-droplet"
    @Published var status = "Vérification de l’installation…"
    private var host: DropletHost?
    private var installation: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Folder Preview Droplet.app") }
    public func activate(host: DropletHost) throws { self.host = host; refresh() }
    public func deactivate() { host = nil }
    func refresh() {
        status = FileManager.default.fileExists(atPath: installation.path) ? "Extension installée · activation à vérifier dans macOS" : "Le composant Quick Look doit être installé"
    }
    func install() {
        guard host?.environment.isHarness != true else { status = "Aperçu de développement · installation inactive"; return }
        do {
            if !FileManager.default.fileExists(atPath: installation.path) {
                guard let bundle = Bundle(for: FolderPreviewDropletPrincipal.self).resourceURL?.appendingPathComponent("Assets/Companion/Folder Preview Droplet.app"), FileManager.default.fileExists(atPath: bundle.path) else { status = "Composant manquant : réinstallez le droplet complet."; return }
                try FileManager.default.createDirectory(at: installation.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundle, to: installation)
            }
            guard Bundle(url: installation)?.bundleIdentifier == "be.nicolasdellim.folderpreviewdroplet" else { status = "Cet emplacement contient une autre application."; return }
            _ = host?.workspace.open(installation); refresh()
        } catch { status = "Installation impossible : \(error.localizedDescription)" }
    }
    func settings() { guard host?.environment.isHarness != true else { return }; _ = host?.workspace.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView { AnyView(PreviewSettings(model: self)) }
    public var settingsSearchEntries: [SettingsSearchEntry] { [SettingsSearchEntry(title: "Prévisualiser les dossiers et archives", keywords: ["Finder", "Quick Look", "Espace", "SVG", "PDF", "miniatures", "grille", "colonnes"])] }
}
private struct PreviewSettings: View {
    @ObservedObject var model: FolderPreviewDroplet
    var body: some View {
        DropletSettingsPane {
            DropletSettingsCard {
                DropletControlRow(title: "Aperçu du Finder", infoTip: model.status) {
                    Button("Installer / ouvrir") { model.install() }.buttonStyle(DroppyAccentButtonStyle(size: .small))
                }
                DropletControlRow(title: model.status) {
                    Button("Vérifier") { model.refresh() }.buttonStyle(DroppyQuietButtonStyle(size: .small))
                }
                DropletControlRow(title: "Extensions Coup d’œil de macOS") {
                    Button("Réglages Système…") { model.settings() }.buttonStyle(DroppyQuietButtonStyle(size: .small))
                }
            }
            DropletSettingsCard {
                DropletStackedRow(title: "Activation") {
                    Text("Activez Folder Preview Droplet dans Réglages Système → Général → Ouverture et extensions → Coup d’œil (Quick Look). Les intitulés varient selon macOS.").foregroundStyle(.secondary)
                }
                DropletStackedRow(title: "La fenêtre native") {
                    Text("Dans le Finder, sélectionnez un dossier ou une archive puis appuyez sur Espace ou ⌘Y. La liste arborescente et la grille restent dans la fenêtre Quick Look de macOS.").foregroundStyle(.secondary)
                }
                DropletStackedRow(title: "Présentation et comportement") {
                    Text("Le menu ⚙︎, en bas de l’aperçu, règle la vue, les miniatures, le texte, les fichiers masqués et les tailles. Un clic droit sur les en-têtes configure les colonnes.").foregroundStyle(.secondary)
                }
                DropletStackedRow(title: "Désactivation") {
                    Text("L’extension système est indépendante du chargement du droplet. Pour la désactiver, utilisez également son interrupteur dans les extensions macOS.").foregroundStyle(.secondary)
                }
            }
        }.onAppear { model.refresh() }
    }
}
