import AppKit
import SwiftUI

struct ExperienceEditorView: View {
    @Environment(AppDataStore.self) private var store
    @State var experience: ExperienceBullet
    let settings: AppSettings?
    @State private var variantPendingDeletion: ExperienceVariation?
    @State private var showDeleteVariantConfirmation = false

    var allExperiences: [ExperienceBullet] { store.experiences }
    var employments: [Employment] { store.employments }
    var applications: [JobApplication] { store.applications }
    var documents: [GeneratedDocument] { store.documents }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                editorHeader
                baseBulletPanel
                variantsPanel
                if experience.isPersonalProject { personalProjectPanel } else { sourcePanel }
                classificationPanel
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: persistenceFingerprint) { _, _ in persist() }
        .confirmationDialog("Delete this variant?", isPresented: $showDeleteVariantConfirmation, presenting: variantPendingDeletion) { variant in
            Button("Delete \(variant.displayName)", role: .destructive) { deleteVariant(variant.id) }
            Button("Cancel", role: .cancel) {}
        } message: { variant in
            Text("This removes \(variant.displayName) from the experience and resets applications using it back to Base.")
        }
    }

    private var persistenceFingerprint: String {
        [experience.id.uuidString, experience.experienceType, experience.company, experience.role,
         experience.projectName, experience.bulletText, experience.variationsText, experience.skillsText,
         experience.roleCategoryRaw, experience.impactLevelRaw,
         String(experience.usableInResume), String(experience.usableInCoverLetter),
         experience.referenceURL, experience.resumeDisplayName,
         experience.employmentID?.uuidString ?? ""].joined(separator: "\u{1F}")
    }

    private var assignedEmployment: Employment? {
        guard let id = experience.employmentID else { return nil }
        return employments.first { $0.id == id }
    }
    private var hasAssignedEmployment: Bool { assignedEmployment != nil }

    private func persist() {
        experience.updatedAt = Date()
        guard let settings else { return }
        do {
            try WorkspaceSyncService.persistExperience(experience, allExperiences: allExperiences, settings: settings)
            if let idx = store.experiences.firstIndex(where: { $0.id == experience.id }) {
                store.experiences[idx] = experience
            }
        } catch { print("ApplyKit experience persistence failed: \(error.localizedDescription)") }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Project or experience title", text: $experience.projectName)
                .font(.system(size: 26, weight: .semibold)).textFieldStyle(.plain)
            Text([experience.company, experience.role].filter { !$0.trimmed.isEmpty }.joined(separator: " - "))
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                ExperienceBadge(experience.roleCategoryRaw, style: .category)
                ExperienceBadge(experience.impactLevelRaw, style: .impact)
                Spacer()
                if experience.usableInResume { Label("Resume", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary) }
                if experience.usableInCoverLetter { Label("Cover Letter", systemImage: "envelope").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.bottom, 2)
    }

    private var baseBulletPanel: some View {
        DetailPanel("Base Bullet") {
            TextEditor(text: $experience.bulletText).font(.body.monospaced()).frame(minHeight: 160)
            HStack {
                Text("Default wording. Tune it for a specific JD inside the application editor after selecting this experience.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Use in resume", isOn: $experience.usableInResume)
                Toggle("Use in cover letter", isOn: $experience.usableInCoverLetter)
            }
        }
    }

    private var variantsPanel: some View {
        DetailPanel("Variants") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Named alternatives for this experience. Applications can choose Base or one of these variants.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { addVariant() } label: { Label("New Variant", systemImage: "plus") }.controlSize(.small)
                }
                if experience.variations.isEmpty {
                    Text("No variants yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(experience.variations) { variation in
                        ExperienceVariantEditorCard(variation: variantBinding(for: variation.id), usageText: usageText(for: variation.id), onDelete: { requestDeleteVariant(variation.id) })
                    }
                }
            }
        }
    }

    private var sourcePanel: some View {
        DetailPanel("Source") {
            LabeledControl("Employment") {
                Picker("Employment", selection: employmentSelection) {
                    Text("(Unassigned)").tag(UUID?.none)
                    ForEach(employments) { emp in Text(employmentLabel(emp)).tag(UUID?.some(emp.id)) }
                }
            }
            if hasAssignedEmployment {
                Text("Company, role, and type are inherited from the selected employment. Edit those in Employments.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Type") { TextField("Work, Project, Open Source", text: $experience.experienceType).textFieldStyle(.roundedBorder).disabled(hasAssignedEmployment) }
                LabeledControl("Company") { TextField("Company", text: $experience.company).textFieldStyle(.roundedBorder).disabled(hasAssignedEmployment) }
            }
            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Role") { TextField("Role", text: $experience.role).textFieldStyle(.roundedBorder).disabled(hasAssignedEmployment) }
                LabeledControl("Reference") {
                    TextField("URL or note", text: hasAssignedEmployment
                        ? Binding(get: { assignedEmployment?.referenceURL ?? "" }, set: { _ in })
                        : $experience.referenceURL).textFieldStyle(.roundedBorder).disabled(hasAssignedEmployment)
                }
            }
        }
    }

    private var personalProjectPanel: some View {
        DetailPanel("Project") {
            Label("Personal projects are independent from employments and appear in the application Selected Projects section.", systemImage: "person.crop.square").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Type") {
                    Picker("Type", selection: $experience.experienceType) {
                        Text(ExperienceCategory.project.rawValue).tag(ExperienceCategory.project.rawValue)
                        Text(ExperienceCategory.openSource.rawValue).tag(ExperienceCategory.openSource.rawValue)
                    }
                }
                LabeledControl("Reference") { TextField("GitHub, demo, paper, or portfolio URL", text: $experience.referenceURL).textFieldStyle(.roundedBorder) }
            }
            LabeledControl("Resume Title Override") {
                TextField(
                    "Leave blank to use project name + reference URL",
                    text: $experience.resumeDisplayName
                )
                .textFieldStyle(.roundedBorder)
                .help("Raw LaTeX passed directly to the resume. Example: \\ulhref{https://github.com/you/proj}{Project Name} (700+ Stars)")
            }
        }
    }

    private var classificationPanel: some View {
        DetailPanel("Classification") {
            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Role Fit") {
                    Picker("Role Fit", selection: $experience.roleCategoryRaw) {
                        ForEach(RoleCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
                LabeledControl("Impact") {
                    Picker("Impact", selection: $experience.impactLevelRaw) {
                        ForEach(ImpactLevel.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
            }
            LabeledControl("Skills") { TextField("Comma-separated skills", text: $experience.skillsText).textFieldStyle(.roundedBorder) }
            ChipCloud(values: experience.parsedSkills, limit: 18)
        }
    }

    private var employmentSelection: Binding<UUID?> {
        Binding(get: { experience.employmentID }, set: { newID in
            experience.employmentID = newID
            if let newID, let emp = employments.first(where: { $0.id == newID }) {
                experience.company = emp.companyName; experience.role = emp.role
                experience.experienceType = emp.experienceTypeRaw; experience.referenceURL = emp.referenceURL
            }
        })
    }

    private func employmentLabel(_ employment: Employment) -> String {
        let parts = [employment.companyName, employment.role].filter { !$0.trimmed.isEmpty }
        return parts.isEmpty ? "Untitled Employment" : parts.joined(separator: " - ")
    }

    private func addVariant() {
        var variations = experience.variations
        variations.append(ExperienceVariation(name: ExperienceVariation.defaultName(existing: variations), bulletText: experience.bulletText))
        experience.variations = variations; persist()
    }

    private func variantBinding(for variantID: UUID) -> Binding<ExperienceVariation> {
        Binding(get: { experience.variations.first { $0.id == variantID } ?? ExperienceVariation(name: "Variant") },
                set: { newValue in
                    var variations = experience.variations
                    guard let index = variations.firstIndex(where: { $0.id == variantID }) else { return }
                    var updated = newValue; updated.updatedAt = Date(); variations[index] = updated
                    experience.variations = variations; persist()
                })
    }

    private func requestDeleteVariant(_ variantID: UUID) {
        variantPendingDeletion = experience.variations.first { $0.id == variantID }
        showDeleteVariantConfirmation = true
    }

    private func deleteVariant(_ variantID: UUID) {
        var variations = experience.variations; variations.removeAll { $0.id == variantID }; experience.variations = variations
        for i in 0..<store.applications.count where store.applications[i].selectedVariantID(for: experience.id) == variantID {
            store.applications[i].setVariant(nil, for: experience.id)
            guard let settings else { continue }
            let appID = store.applications[i].id
            let docs = store.documents.filter { $0.applicationID == appID }
            try? WorkspaceSyncService.persistApplication(store.applications[i], documents: docs, settings: settings)
        }
        persist()
    }

    private func usageText(for variantID: UUID) -> String {
        let titles = applications.filter { $0.selectedVariantID(for: experience.id) == variantID }.map(\.displayTitle).sorted()
        return titles.isEmpty ? "Not selected by any application yet." : "Used by \(titles.joined(separator: ", "))"
    }
}
