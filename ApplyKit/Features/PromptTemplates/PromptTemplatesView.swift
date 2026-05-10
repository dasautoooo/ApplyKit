//
//  PromptTemplatesView.swift
//  ApplyKit
//

import SwiftUI

struct PromptTemplatesView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var selectedID: UUID?
    @State private var templatePendingDeletion: PromptTemplate?
    @State private var showDeleteConfirmation = false
    @State private var sidebarWidth: CGFloat = 320

    var body: some View {
        StableSidebarSplit(
            sidebarWidth: $sidebarWidth,
            minWidth: 280,
            maxWidth: 400
        ) {
            List(selection: $selectedID) {
                ForEach(store.promptTemplates) { template in
                    VStack(alignment: .leading) {
                        Text(template.name)
                        Text(template.purposeRaw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(template.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            requestDelete(template)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: requestDelete)
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            if let selectedTemplate {
                PromptTemplateEditorView(template: selectedTemplate, settings: settings)
                    .id(selectedID)
            } else {
                ContentUnavailableView("Select a prompt template", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: add) {
                    Label("New Template", systemImage: "plus")
                }
            }

            ToolbarItem {
                Button(role: .destructive, action: requestDeleteSelected) {
                    Label("Delete Template", systemImage: "trash")
                }
                .disabled(selectedTemplate == nil)
            }
        }
        .confirmationDialog(
            "Delete this prompt template?",
            isPresented: $showDeleteConfirmation,
            presenting: templatePendingDeletion
        ) { template in
            Button("Delete \(template.name)", role: .destructive) {
                delete(template, deletingSourceFile: false)
            }
            Button("Delete \(template.name) and Source File", role: .destructive) {
                delete(template, deletingSourceFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { template in
            Text("Delete removes the prompt template from the local cache only. Delete and Source File also removes its YAML file from the workspace.")
        }
    }

    private var selectedTemplate: PromptTemplate? {
        guard let selectedID else { return nil }
        return store.promptTemplates.first { $0.id == selectedID }
    }

    private func add() {
        let template = PromptTemplate(name: "New Template", purpose: .analyzeJob, templateText: "")
        store.promptTemplates.append(template)
        store.promptTemplates.sort { $0.name < $1.name }
        try? WorkspaceSyncService.persistPromptTemplate(template, settings: settings)
        selectedID = template.id
    }

    private func requestDeleteSelected() {
        guard let selectedTemplate else { return }
        requestDelete(selectedTemplate)
    }

    private func requestDelete(offsets: IndexSet) {
        guard let index = offsets.first else { return }
        requestDelete(store.promptTemplates[index])
    }

    private func requestDelete(_ template: PromptTemplate) {
        templatePendingDeletion = template
        showDeleteConfirmation = true
    }

    private func delete(_ template: PromptTemplate, deletingSourceFile: Bool) {
        if deletingSourceFile {
            WorkspaceSyncService.deletePromptTemplateFile(template, settings: settings)
        }
        store.promptTemplates.removeAll { $0.id == template.id }
        if selectedID == template.id {
            selectedID = nil
        }
        templatePendingDeletion = nil
    }
}

struct PromptTemplateEditorView: View {
    @Environment(AppDataStore.self) private var store
    @State var template: PromptTemplate
    let settings: AppSettings?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                DetailPanel("Template Details") {
                    LabeledControl("Purpose") {
                        Picker("Purpose", selection: $template.purposeRaw) {
                            ForEach(PromptPurpose.allCases) { purpose in
                                Text(purpose.rawValue).tag(purpose.rawValue)
                            }
                        }
                    }
                }

                DetailPanel("Prompt Body") {
                    Text("Available placeholders: {{company}}, {{job_title}}, {{location}}, {{job_url}}, {{job_description}}, {{experience_items}}, {{notes}}")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $template.templateText)
                        .font(.body.monospaced())
                        .frame(minHeight: 420)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: templatePersistenceFingerprint) { _, _ in
            persistTemplateChanges()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $template.name)
                .font(.system(size: 26, weight: .semibold))
                .textFieldStyle(.plain)

            HStack(spacing: 8) {
                ExperienceBadge(template.purposeRaw, style: .category)
                if template.isDefault {
                    ExperienceBadge("Default", style: .neutral)
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var templatePersistenceFingerprint: String {
        [
            template.id.uuidString,
            template.name,
            template.purposeRaw,
            template.templateText,
            String(template.isDefault)
        ].joined(separator: "\u{1F}")
    }

    private func persistTemplateChanges() {
        template.updatedAt = Date()
        guard let settings else { return }
        do {
            try WorkspaceSyncService.persistPromptTemplate(template, settings: settings)
            if let idx = store.promptTemplates.firstIndex(where: { $0.id == template.id }) {
                store.promptTemplates[idx] = template
            }
        } catch {
            print("ApplyKit prompt template persistence failed: \(error.localizedDescription)")
        }
    }
}
