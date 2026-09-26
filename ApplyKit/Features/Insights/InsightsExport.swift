//
//  InsightsExport.swift
//  ApplyKit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Renders Insights views off screen as PNG or PDF for sharing. Always light on white, so a
/// chart reads the same pasted into a document or posted anywhere, whatever the app's theme.
@MainActor
enum InsightsExport {
    static let scale: CGFloat = 2

    static func pngData(_ view: some View, width: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: framed(view, width: width))
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// Vector PDF, one page sized to the content.
    static func pdfData(_ view: some View, width: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: framed(view, width: width))
        let data = NSMutableData()
        renderer.render { size, render in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }

    static func copyImage(_ view: some View, width: CGFloat) {
        guard let data = pngData(view, width: width), let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func save(_ view: some View, width: CGFloat, name: String, as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = type == .pdf ? pdfData(view, width: width) : pngData(view, width: width)
        try? data?.write(to: url)
    }

    private static func framed(_ view: some View, width: CGFloat) -> some View {
        view
            .frame(width: width)
            .padding(24)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.isInsightsExport, true)
    }
}

extension EnvironmentValues {
    /// Set while rendering for sharing, so hover hints — meaningless in a still image — drop out.
    @Entry var isInsightsExport = false
}

/// A rendered chart handed to the system share menu. Rendered only when a destination is
/// picked, not every time the menu is drawn.
///
/// `@unchecked Sendable`: the view is only ever rendered on the main actor, inside
/// `MainActor.run`, which is all the export closure's `@Sendable` requirement protects.
struct InsightsShareItem: Transferable, @unchecked Sendable {
    let name: String
    let width: CGFloat
    let content: AnyView

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await MainActor.run(body: { InsightsExport.pngData(item.content, width: item.width) }) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { "\($0.name).png" }
    }
}

/// Share, copy, or save a view as an image or PDF.
struct InsightsShareMenu: View {
    /// Also the suggested file name.
    let name: String
    /// Width the export is laid out at, independent of the window.
    let width: CGFloat
    var label: String?
    /// Only a description of the view; nothing is rendered until an option is picked.
    let content: AnyView

    var body: some View {
        Menu {
            ShareLink(
                item: InsightsShareItem(name: name, width: width, content: content),
                preview: SharePreview(name, image: Image(systemName: "chart.bar.xaxis"))
            ) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button {
                InsightsExport.copyImage(content, width: width)
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            Divider()
            Button("Save as PNG…") { InsightsExport.save(content, width: width, name: name, as: .png) }
            Button("Save as PDF…") { InsightsExport.save(content, width: width, name: name, as: .pdf) }
        } label: {
            if let label {
                Label(label, systemImage: "square.and.arrow.up")
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .help("Share, copy, or save as an image or PDF")
    }
}
