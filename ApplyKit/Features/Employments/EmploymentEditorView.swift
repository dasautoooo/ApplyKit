import AppKit
import SwiftUI

struct EmploymentEditorView: View {
    @Environment(AppDataStore.self) private var store
    @State var employment: Employment
    let settings: AppSettings?

    var allEmployments: [Employment] { store.employments }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                DetailPanel("Role Details") {
                    HStack(alignment: .top, spacing: 16) {
                        LabeledControl("Location") { TextField("Location", text: $employment.location).textFieldStyle(.roundedBorder) }
                        LabeledControl("Reference") { TextField("URL or note", text: $employment.referenceURL).textFieldStyle(.roundedBorder) }
                    }
                    LabeledControl("Role Description") {
                        TextEditor(text: $employment.roleDescription).font(.body.monospaced()).frame(minHeight: 72)
                    }
                    Text("Appears as the first bullet in the resume. Describe the role in one sentence.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DetailPanel("Dates and Resume Order") {
                    HStack(alignment: .top, spacing: 16) {
                        OptionalDatePicker(title: "Start", date: $employment.startDate)
                        OptionalDatePicker(title: "End (leave off for Present)", date: $employment.endDate)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    HStack {
                        Stepper(value: $employment.displayOrder, in: 0...999) {
                            Text("Display order \(employment.displayOrder)").monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        Text("Lower numbers appear higher in the resume.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DetailPanel("Notes") { TextEditor(text: $employment.notes).frame(minHeight: 100) }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(employment.displayTitle)
        .onChange(of: persistenceFingerprint) { _, _ in persist() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Company name", text: $employment.companyName)
                .font(.system(size: 26, weight: .semibold)).textFieldStyle(.plain)
            TextField("Role / title", text: $employment.role)
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).textFieldStyle(.plain)
            HStack(spacing: 8) {
                if !employment.dateRangeText().isEmpty { ExperienceBadge(employment.dateRangeText(), style: .neutral) }
            }.padding(.top, 2)
        }.padding(.bottom, 2)
    }

    private var persistenceFingerprint: String {
        [employment.id.uuidString, employment.companyName, employment.role, employment.location,
         WorkspaceDateCodec.string(from: employment.startDate) ?? "",
         WorkspaceDateCodec.string(from: employment.endDate) ?? "",
         String(employment.displayOrder), employment.referenceURL, employment.notes, employment.roleDescription
        ].joined(separator: "\u{1F}")
    }

    private func persist() {
        employment.experienceTypeRaw = ExperienceCategory.work.rawValue
        employment.updatedAt = Date()
        guard let settings else { return }
        do {
            try WorkspaceSyncService.persistEmployment(employment, allEmployments: allEmployments, settings: settings)
            if let idx = store.employments.firstIndex(where: { $0.id == employment.id }) {
                store.employments[idx] = employment
            }
        } catch { print("ApplyKit employment persistence failed: \(error.localizedDescription)") }
    }
}

struct EmploymentSummaryRow: View {
    let employment: Employment; let attachedBulletCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(employment.displayTitle).font(.headline).lineLimit(1)
            Text([employment.role, employment.location].filter { !$0.trimmed.isEmpty }.joined(separator: " - "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                let range = employment.dateRangeText()
                if !range.isEmpty { Text(range).font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Text("\(attachedBulletCount) bullet\(attachedBulletCount == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 2)
    }
}

struct DeleteEmploymentDialog: View {
    let employment: Employment; let attachedBulletCount: Int
    @Binding var shouldDeleteSourceFile: Bool
    let onCancel: () -> Void; let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete this employment?").font(.headline)
                    Text(employment.displayTitle).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if attachedBulletCount > 0 {
                Text("\(attachedBulletCount) attached bullet\(attachedBulletCount == 1 ? "" : "s") will be unlinked but not deleted.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Also delete source file", isOn: $shouldDeleteSourceFile)
            Text(shouldDeleteSourceFile
                ? "Removes the employment from the local cache and deletes its YAML file from the workspace, updating the employments index."
                : "Removes the employment from the local cache. The YAML file in the workspace is left untouched.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) { onDelete() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 440)
    }
}
