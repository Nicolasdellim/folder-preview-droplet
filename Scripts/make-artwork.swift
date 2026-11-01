import AppKit
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func png(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try data.write(to: url)
}
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
NSWorkspace.shared.icon(for: .folder).draw(in: NSRect(x: 92, y: 140, width: 840, height: 740))
let plate = NSBezierPath(roundedRect: NSRect(x: 565, y: 110, width: 330, height: 265), xRadius: 95, yRadius: 95)
NSColor.systemBlue.setFill(); plate.fill()
if let eye = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 170, weight: .medium).applying(.init(paletteColors: [.white]))
    eye.withSymbolConfiguration(config)?.draw(in: NSRect(x: 615, y: 172, width: 230, height: 140))
}
icon.unlockFocus()
try png(icon, to: root.appendingPathComponent("Assets/FolderPreviewDroplet.png"))
let drawing = NSImage(size: NSSize(width: 640, height: 400))
drawing.lockFocus()
NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.2, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 400)).fill()
for i in 0..<7 {
    NSColor(calibratedHue: CGFloat(i) / 10 + 0.45, saturation: 0.65, brightness: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 40 + i * 80, y: 50 + i * 22, width: 62, height: 80 + i * 20), xRadius: 12, yRadius: 12).fill()
}
("Aperçu d’image" as NSString).draw(at: NSPoint(x: 42, y: 330), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.white])
drawing.unlockFocus()
try png(drawing, to: root.appendingPathComponent("Demo/Images/Couleurs.png"))
let pdfURL = root.appendingPathComponent("Demo/Documents/Exemple.pdf")
var box = CGRect(x: 0, y: 0, width: 600, height: 800)
let consumer = CGDataConsumer(url: pdfURL as CFURL)!
let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
for number in 1...3 {
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)); context.fill(box)
    context.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1)); context.fill(CGRect(x: 45, y: 610, width: 510, height: 130))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    ("Document de démonstration\nPage \(number) / 3" as NSString).draw(in: NSRect(x: 55, y: 400, width: 490, height: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: NSColor.labelColor])
    NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
}
context.closePDF()
let rich = NSAttributedString(string: "Document enrichi\nPrévisualisation dans la grille native.", attributes: [.font: NSFont.systemFont(ofSize: 20)])
let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
try rtf.write(to: root.appendingPathComponent("Demo/Documents/Exemple.rtf"))
