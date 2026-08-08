//
//  ResumePDFInspector.swift
//  ApplyKit
//
//  Reads a generated résumé PDF back: how many pages it actually came to, and
//  what text it yields.
//
//  Both matter to the skill's final checks. The page count settles the two-page
//  budget, which is otherwise only an estimate. The extracted text is what an
//  ATS would see — if it comes back empty, garbled, or out of order, that is a
//  finding in itself, however good the résumé looks on screen.
//

import Foundation
import PDFKit

enum ResumePDFInspector {
    struct Rendered {
        let pageCount: Int
        /// Page-by-page text, so reading order and page breaks stay visible to
        /// the reviewer rather than being flattened away.
        let pages: [String]

        var text: String {
            pages.enumerated()
                .map { "--- page \($0.offset + 1) ---\n\($0.element.trimmed)" }
                .joined(separator: "\n\n")
        }

        var isTextEmpty: Bool { pages.allSatisfy { $0.trimmed.isEmpty } }
    }

    static func inspect(path: String) -> Rendered? {
        let trimmed = path.trimmed
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: trimmed),
              let document = PDFDocument(url: URL(fileURLWithPath: trimmed)) else { return nil }

        let pages = (0..<document.pageCount).map { index in
            document.page(at: index)?.string ?? ""
        }
        return Rendered(pageCount: document.pageCount, pages: pages)
    }
}
