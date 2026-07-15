//
//  MasterResumeEditorGeneration.swift
//  ApplyKit
//
//  Transient PDF preview for a master resume. Output lives under
//  master-resumes/<slug>/ and is overwritten on each generation; no
//  GeneratedDocument manifest is recorded.
//

import AppKit
import SwiftUI

extension MasterResumeEditorView {
    var previewSection: some View {
        DetailPanel("Preview") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await generatePreview() }
                    } label: {
                        Label(isGeneratingPreview ? "Generating…" : "Generate Preview PDF", systemImage: "doc.richtext")
                    }
                    .disabled(isGeneratingPreview || settings == nil)

                    if let previewTexPath {
                        Button {
                            FileOpenService.open(path: previewTexPath)
                        } label: {
                            Label("Open TeX", systemImage: "doc")
                        }
                        .controlSize(.small)
                    }

                    if let previewPDFPath, FileManager.default.fileExists(atPath: previewPDFPath) {
                        Button {
                            FileOpenService.open(path: previewPDFPath)
                        } label: {
                            Label("Open PDF", systemImage: "doc.richtext")
                        }
                        .controlSize(.small)

                        Button {
                            FileOpenService.reveal(path: previewPDFPath)
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .controlSize(.small)
                    }

                    Spacer()
                }

                Text("Builds a PDF of this preset using your profile and the resume template, without an application. Regenerating overwrites the previous preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !previewBuildLog.trimmed.isEmpty {
                    DisclosureGroup("Build log") {
                        Text(previewBuildLog)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    func generatePreview() async {
        guard let settings else {
            activityMonitor.fail("Open Settings and choose a workspace before generating files.")
            return
        }
        // Flush pending edits so the preview reflects what's on screen.
        persistMasterResumeChanges()

        let employmentsByID = ResumeContentGrouping.employmentsByID(employments)
        let employmentOrderByID: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0.displayOrder) }
        )
        func sortedByEmployment(_ bullets: [ExperienceBullet]) -> [ExperienceBullet] {
            bullets.sorted { lhs, rhs in
                let lhsOrder = lhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                let rhsOrder = rhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }
        }
        let selectedIDs = masterResume.selectedExperienceIDs
        let selectedProjectIDs = masterResume.selectedProjectIDs
        let selectedExperiences = sortedByEmployment(experiences.filter {
            selectedIDs.contains($0.id) && ResumeContentGrouping.isWorkLike($0, employmentsByID: employmentsByID)
        })
        let selectedProjects = sortedByEmployment(experiences.filter {
            selectedProjectIDs.contains($0.id) && ResumeContentGrouping.isProjectLike($0, employmentsByID: employmentsByID)
        })

        isGeneratingPreview = true
        activityMonitor.start("Generating master resume preview…")
        do {
            let result = try WorkspaceService.generateMasterResumePreview(
                masterResume,
                selectedExperiences: selectedExperiences,
                selectedProjects: selectedProjects,
                employments: employments,
                profile: store.profile,
                settings: settings
            )
            previewTexPath = result.texURL.path

            let build = try await LatexService.build(texPath: result.texURL.path, command: settings.latexBuildCommand)
            previewBuildLog = build.combinedOutput
            isGeneratingPreview = false
            if build.succeeded {
                previewPDFPath = result.pdfURL.path
                FileOpenService.open(path: result.pdfURL.path)
                let base = "Preview generated."
                let msg = result.warnings.isEmpty ? base : base + " " + result.warnings.joined(separator: " ")
                activityMonitor.succeed(msg)
            } else {
                previewPDFPath = FileManager.default.fileExists(atPath: result.pdfURL.path) ? result.pdfURL.path : nil
                activityMonitor.fail("Preview built with errors — see the build log.")
            }
        } catch {
            isGeneratingPreview = false
            activityMonitor.fail(error.localizedDescription)
        }
    }

    /// Enables "Open PDF" for a preview generated in an earlier session.
    func locateExistingPreview() {
        guard previewPDFPath == nil, let settings,
              let workspace = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = workspace.startAccessingSecurityScopedResource()
        defer { if didStart { workspace.stopAccessingSecurityScopedResource() } }
        let resumeSlug = WorkspaceFiles.slug(from: masterResume.name, fallback: masterResume.id.uuidString.lowercased())
        let folder = workspace
            .appendingPathComponent(WorkspaceFiles.masterResumesDirectory, isDirectory: true)
            .appendingPathComponent(resumeSlug, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        previewPDFPath = files.first { $0.pathExtension == "pdf" }?.path
        previewTexPath = files.first { $0.pathExtension == "tex" }?.path
    }
}
