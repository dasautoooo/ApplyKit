//
//  FilterControls.swift
//  ApplyKit
//

import AppKit
import SwiftUI
struct ApplicationFilterMenu: View {
    let title: String
    let value: String
    let systemImage: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(optionLabel(option), systemImage: "checkmark")
                    } else {
                        Text(optionLabel(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(displayValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func optionLabel(_ option: String) -> String {
        if option == "All" {
            switch title {
            case "Status": "All Statuses"
            case "Priority": "All Priorities"
            default: "All"
            }
        } else {
            option
        }
    }

    private var displayValue: String {
        switch value {
        case "All": "All"
        default: value
        }
    }
}

struct ApplicationScopeTabs: View {
    @Binding var selection: String
    let counts: [ApplicationListScope: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ApplicationListScope.allCases) { scope in
                Button {
                    selection = scope.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Text(scope.rawValue)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(counts[scope, default: 0])")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isSelected(scope) ? .primary : .secondary)
                            .opacity(isSelected(scope) ? 0.78 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSelected(scope) ? .primary : .secondary)
                    .background {
                        if isSelected(scope) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .separatorColor).opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func isSelected(_ scope: ApplicationListScope) -> Bool {
        selection == scope.rawValue
    }
}

struct ExperienceFilterMenu: View {
    let title: String
    let value: String
    let systemImage: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(displayValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var displayValue: String {
        if value.hasPrefix("All ") { return "All" }
        return value
    }
}

struct FilterPicker<Content: View>: View {
    let title: String
    @Binding var selection: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Picker(title, selection: $selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
