//
//  ResumePageLayout.swift
//  ApplyKit
//
//  Per-application page settings: body font size and page margin.
//
//  Two applications can want the same content set differently — a role worth a
//  dense two pages and one worth a roomy one — so these live on the
//  application rather than the shared template. The template carries
//  placeholders for both; see `ResumeRenderer.applyPageLayout`.
//
//  Bounds are the document class's, not preferences: `resume.cls` is built on
//  the standard classes, which accept only 10, 11 or 12 pt. A margin below
//  ~0.25in runs into most printers' unprintable edge, and the skill's own
//  guidance is to cut content rather than shrink the page — so tightening is
//  allowed, but it is the candidate's call and never the model's.
//

import Foundation

enum ResumePageLayout {
    static let fontSizes = [10, 11, 12]
    static let defaultFontSizePt = 10

    static let marginRange: ClosedRange<Double> = 0.3...1.0
    static let defaultMarginInches = 0.3

    static func clampFontSize(_ value: Int) -> Int {
        fontSizes.contains(value) ? value : defaultFontSizePt
    }

    static func clampMargin(_ value: Double) -> Double {
        guard value.isFinite else { return defaultMarginInches }
        let rounded = (value * 20).rounded() / 20      // nearest 0.05in
        return min(max(rounded, marginRange.lowerBound), marginRange.upperBound)
    }

    /// "0.4in", with no trailing zeros LaTeX would read as false precision.
    static func marginText(_ value: Double) -> String {
        let clamped = clampMargin(value)
        let text = clamped == clamped.rounded()
            ? String(Int(clamped))
            : String(format: "%.2f", clamped).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return "\(text)in"
    }
}
