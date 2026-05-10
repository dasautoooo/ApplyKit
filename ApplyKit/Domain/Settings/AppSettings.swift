//
//  AppSettings.swift
//  ApplyKit
//

import Foundation
import Observation

@Observable final class AppSettings {
    var workspacePath: String {
        get { _workspacePath }
        set { _workspacePath = newValue; ud.set(newValue, forKey: Keys.workspacePath) }
    }
    private var _workspacePath: String

    var workspaceBookmark: Data? {
        get { _workspaceBookmark }
        set { _workspaceBookmark = newValue; ud.set(newValue, forKey: Keys.workspaceBookmark) }
    }
    private var _workspaceBookmark: Data?

    var codexCLIPath: String {
        get { _codexCLIPath }
        set { _codexCLIPath = newValue; ud.set(newValue, forKey: Keys.codexCLIPath) }
    }
    private var _codexCLIPath: String

    var claudeCLIPath: String {
        get { _claudeCLIPath }
        set { _claudeCLIPath = newValue; ud.set(newValue, forKey: Keys.claudeCLIPath) }
    }
    private var _claudeCLIPath: String

    var preferredAIBackendRaw: String {
        get { _preferredAIBackendRaw }
        set { _preferredAIBackendRaw = newValue; ud.set(newValue, forKey: Keys.preferredAIBackendRaw) }
    }
    private var _preferredAIBackendRaw: String

    var latexBuildCommand: String {
        get { _latexBuildCommand }
        set { _latexBuildCommand = newValue; ud.set(newValue, forKey: Keys.latexBuildCommand) }
    }
    private var _latexBuildCommand: String

    var externalEditorPath: String {
        get { _externalEditorPath }
        set { _externalEditorPath = newValue; ud.set(newValue, forKey: Keys.externalEditorPath) }
    }
    private var _externalEditorPath: String

    var resumeTemplatePath: String {
        get { _resumeTemplatePath }
        set { _resumeTemplatePath = newValue; ud.set(newValue, forKey: Keys.resumeTemplatePath) }
    }
    private var _resumeTemplatePath: String

    var resumeTemplateBookmark: Data? {
        get { _resumeTemplateBookmark }
        set { _resumeTemplateBookmark = newValue; ud.set(newValue, forKey: Keys.resumeTemplateBookmark) }
    }
    private var _resumeTemplateBookmark: Data?

    var coverLetterTemplatePath: String {
        get { _coverLetterTemplatePath }
        set { _coverLetterTemplatePath = newValue; ud.set(newValue, forKey: Keys.coverLetterTemplatePath) }
    }
    private var _coverLetterTemplatePath: String

    var coverLetterTemplateBookmark: Data? {
        get { _coverLetterTemplateBookmark }
        set { _coverLetterTemplateBookmark = newValue; ud.set(newValue, forKey: Keys.coverLetterTemplateBookmark) }
    }
    private var _coverLetterTemplateBookmark: Data?

    private let ud = UserDefaults.standard

    init() {
        _workspacePath             = ud.string(forKey: Keys.workspacePath) ?? ""
        _workspaceBookmark         = ud.data(forKey: Keys.workspaceBookmark)
        _codexCLIPath              = ud.string(forKey: Keys.codexCLIPath) ?? ""
        _claudeCLIPath             = ud.string(forKey: Keys.claudeCLIPath) ?? ""
        _preferredAIBackendRaw     = ud.string(forKey: Keys.preferredAIBackendRaw) ?? "Claude"
        _latexBuildCommand         = ud.string(forKey: Keys.latexBuildCommand) ?? "latexmk -pdf -interaction=nonstopmode -synctex=1"
        _externalEditorPath        = ud.string(forKey: Keys.externalEditorPath) ?? ""
        _resumeTemplatePath        = ud.string(forKey: Keys.resumeTemplatePath) ?? ""
        _resumeTemplateBookmark    = ud.data(forKey: Keys.resumeTemplateBookmark)
        _coverLetterTemplatePath   = ud.string(forKey: Keys.coverLetterTemplatePath) ?? ""
        _coverLetterTemplateBookmark = ud.data(forKey: Keys.coverLetterTemplateBookmark)
    }

    var hasConfiguredWorkspace: Bool {
        _workspaceBookmark != nil || !_workspacePath.trimmed.isEmpty
    }

    enum Keys {
        static let workspacePath               = "workspacePath"
        static let workspaceBookmark           = "workspaceBookmark"
        static let codexCLIPath                = "codexCLIPath"
        static let claudeCLIPath               = "claudeCLIPath"
        static let preferredAIBackendRaw       = "preferredAIBackendRaw"
        static let latexBuildCommand           = "latexBuildCommand"
        static let externalEditorPath          = "externalEditorPath"
        static let resumeTemplatePath          = "resumeTemplatePath"
        static let resumeTemplateBookmark      = "resumeTemplateBookmark"
        static let coverLetterTemplatePath     = "coverLetterTemplatePath"
        static let coverLetterTemplateBookmark = "coverLetterTemplateBookmark"
    }
}
