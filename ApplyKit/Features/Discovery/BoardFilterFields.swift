//
//  BoardFilterFields.swift
//  ApplyKit
//
//  The keyword filters a tracked board carries, as one form. Shared by
//  `AddBoardSheet`'s single-board form and `WatchlistPane` (applied to every
//  board added in a batch) so the two can't describe the same three fields
//  differently.
//

import SwiftUI

struct BoardFilterFields: View {
    @Binding var titleKeywords: String
    @Binding var excludeKeywords: String
    @Binding var locationKeywords: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title includes (comma-separated)", text: $titleKeywords,
                  placeholder: "engineer, developer",
                  help: "Only postings whose title contains one of these. Empty = all titles.")
            field("Title excludes (comma-separated)", text: $excludeKeywords,
                  placeholder: "senior, staff",
                  help: "Drop postings whose title contains any of these.")
            field("Location includes (comma-separated)", text: $locationKeywords,
                  placeholder: "remote, toronto",
                  help: "Only postings whose location contains one of these. Empty = all locations.")
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension TrackedBoard {
    /// Applies a filter form's raw comma-separated text to this board.
    mutating func applyFilters(titleKeywords: String, excludeKeywords: String, locationKeywords: String) {
        self.titleKeywords = titleKeywords.commaSeparatedValues
        self.excludeKeywords = excludeKeywords.commaSeparatedValues
        self.locationKeywords = locationKeywords.commaSeparatedValues
    }
}
