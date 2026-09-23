//
//  ResumeEditPlanPrompt.swift
//  ApplyKit
//
//  The output contract appended to "Copy context for ChatGPT": the Resume Edit
//  Plan v1.0 schema, the rules the schema can't express, and every bullet id
//  grouped the way `order` counts them. The reply is read by
//  `ResumeEditPlanImporter`, with no AI in between — so everything the importer
//  checks is spelled out here.
//

import Foundation

enum ResumeEditPlanPrompt {

    /// The section ChatGPT reads last: how to answer, and which ids exist.
    static func outputContract(experiences: [ExperienceBullet], employments: [Employment],
                               selectedIDs: Set<UUID>, variantSelections: [UUID: UUID],
                               roleDescriptions: [UUID: String] = [:],
                               hiddenRoleDescriptions: Set<UUID> = [],
                               hasSummary: Bool, hasEducation: Bool) -> String {
        """
        ## Output format: ApplyKit Resume Edit Plan v1.0

        Write your reasoning first: the fit judgment, what you changed and why, and the full tailored résumé as readable text, so it can be reviewed before anything is applied. Then end the reply with exactly one JSON object in a ```json code block, matching what you wrote. ApplyKit reads only that object: nothing outside it is applied, and a reply with no object, two objects, or an object that breaks these rules is rejected as a whole.

        Rules:
        - `schema_version` is "1.0". `fit_score` is your fit judgment from 0 to 10.
        - `experience` and `projects` together decide every bullet on the résumé. Each bullet marked "on résumé" in the list below must appear exactly once, as `keep`, `rewrite`, or `drop` (to take it off); leaving one out is an error. A bullet marked "not selected" appears only to add it, as `keep` or `rewrite`; leave it out to keep it off.
        - A project is one item with one id, even when it renders as several lines. `keep` keeps all of its lines, `drop` removes the whole project, and `rewrite` replaces all of them with one new wording: for several points, start each point with \\item on its own line in `text` (for example "\\\\item Grew …\\n\\\\item Designed …" in the JSON string); a single point is plain text.
        - Copy every `id` exactly from the list below. Never invent one. An id under "Experience" goes in `experience`; an id under "Projects" goes in `projects`. Each id appears at most once.
        - `order` ranks the kept and rewritten bullets within their group (one employer, or one project group below): 1, 2, 3 … with no gaps or repeats, starting again at 1 in each group. Groups stay in ApplyKit's order. A dropped bullet has `order: null`. An employer's role description can take one of those slots too (see below); when it does, the role line and that employer's bullets are numbered together.
        - `keep` renders the bullet's wording exactly as shown in the résumé above; its `variant_title` and `text` are null.
        - `rewrite` needs `text`, the complete rewritten bullet, and `variant_title`, at most 80 characters naming the angle the rewrite takes (for example "Process Automation and Cost Savings"). Never a generic title such as "Tailored Version".
        - `drop` sets `order`, `variant_title`, and `text` to null.
        - A role description is the one-line scope sentence under an employer, marked `[role description]` in the résumé above. It is not a bullet: never put an `employment_id` in `experience`. To change one, add an entry to `role_descriptions` with that employer's `employment_id`: `keep` shows the current line as it is (use it to bring back one marked hidden), `rewrite` shows it with new wording in `text`, and `hide` leaves it off this résumé. `text` is null unless the action is `rewrite`, which can also add a line to an employer that has none. The line's current position is where it appears among that employer's bullets in the résumé above. To move it, give it an `order`: it is numbered together with the employer's kept and rewritten bullets, top to bottom, so a role line with `order: 1` sits above bullets numbered 2, 3 …, and one with `order: 3` sits between bullets 2 and 4. `order: null` leaves it where it is (a line added to an employer that had none goes at the top), and a hidden line always has `order: null`. List each employer at most once; an employer you don't list keeps its line exactly as it is, in the same place.
        - `summary`: `keep` retains the current summary\(hasSummary ? "" : " (this résumé has none, so use replace or drop)"), `replace` supplies new text, and `drop` removes the section. `text` is null unless the action is `replace`.
        - `skills` replaces the whole Skills section with exactly three rows of `{ "label", "items" }`. Each row must fit on one line of a column 0.74\\textwidth wide. No label or skill may appear twice. `content_width` is always the JSON string "0.74\\\\textwidth".
        - `section_order` lists every section that will render, top to bottom, using only summary, education, skills, experience, projects. \(hasEducation ? "Education always renders, so it is listed." : "This résumé has no Education section, so education is not listed.") Leave out summary when it is dropped, and leave out experience or projects when nothing in them is kept or rewritten.
        - Text you write (rewrites, summary, skills, role descriptions) is plain text: no Markdown and no list markers. Write %, &, _ and # as they are; ApplyKit escapes them. Existing wording may contain LaTeX such as \\texttt{…}, \\ulhref{…}{…} or B\\'{e}zier; ApplyKit renders kept wording as it is, and a rewrite may carry such inline markup over, but never add structural commands such as \\begin, \\end, \\section, \\vspace or \\input, and use \\item only to open a project's points.
        - Every field in the schema is required. Use null where a field doesn't apply, and add no other fields.

        ### Bullet ids by group
        \(idListing(experiences: experiences, employments: employments,
                    selectedIDs: selectedIDs, variantSelections: variantSelections,
                    roleDescriptions: roleDescriptions, hiddenRoleDescriptions: hiddenRoleDescriptions))

        ### JSON Schema
        ```json
        \(schemaJSON)
        ```

        ### Example (shape only: replace every <…> with real values; ids come from the list above)
        ```json
        \(exampleJSON)
        ```
        """
    }

    /// Every bullet, under the group its `order` counts within, and each
    /// employer's id and role-description state. Wording is clipped: the full
    /// text is already in the résumé section above.
    static func idListing(experiences: [ExperienceBullet], employments: [Employment],
                          selectedIDs: Set<UUID>, variantSelections: [UUID: UUID],
                          roleDescriptions: [UUID: String] = [:],
                          hiddenRoleDescriptions: Set<UUID> = []) -> String {
        let employmentsByID = ResumeContentGrouping.employmentsByID(employments)

        func groups(projects: Bool) -> String {
            let bullets = experiences.filter {
                ResumeContentGrouping.isProjectLike($0, employmentsByID: employmentsByID) == projects
            }
            let grouped = Dictionary(grouping: bullets) { $0.employmentID.flatMap { employmentsByID[$0] }?.id }
            let keys = grouped.keys.sorted { lhs, rhs in
                let lo = lhs.flatMap { employmentsByID[$0]?.displayOrder } ?? Int.max
                let ro = rhs.flatMap { employmentsByID[$0]?.displayOrder } ?? Int.max
                return lo != ro ? lo < ro : (lhs?.uuidString ?? "") < (rhs?.uuidString ?? "")
            }
            guard !keys.isEmpty else { return "(none)" }
            return keys.map { key -> String in
                let employment = key.flatMap { employmentsByID[$0] }
                var title = employment.map {
                    $0.role.trimmed.isEmpty ? $0.companyName : "\($0.companyName) — \($0.role)"
                } ?? (projects ? "Personal projects" : "Unassigned")
                // Only work employers carry a role line the plan can decide.
                if let employment, !projects {
                    let override = roleDescriptions[employment.id]?.trimmed ?? ""
                    let line = override.isEmpty ? employment.roleDescription.trimmed : override
                    let state = line.isEmpty ? "none"
                        : hiddenRoleDescriptions.contains(employment.id) ? "hidden" : "shown"
                    title += " (employment_id: \(employment.id.uuidString); role description: \(state))"
                }
                let lines = (grouped[key] ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { bullet -> String in
                        let text = bullet.bulletText(variantID: variantSelections[bullet.id])
                        let marker = selectedIDs.contains(bullet.id) ? "on résumé" : "not selected"
                        return "- \(bullet.id.uuidString) (\(marker)) \(clipped(text))"
                    }
                return "- \(title)\n" + lines.map { "  \($0)" }.joined(separator: "\n")
            }.joined(separator: "\n")
        }

        return """
        Experience (goes in `experience`):
        \(groups(projects: false))

        Projects (goes in `projects`):
        \(groups(projects: true))
        """
    }

    private static func clipped(_ text: String, limit: Int = 70) -> String {
        let flat = ResumeEditPlanImporter.lines(of: text).joined(separator: " / ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)).trimmed + "…"
    }

    /// Shape only: every `<…>` is a placeholder, so nothing in it can be
    /// mistaken for the candidate's own content.
    static let exampleJSON = """
    {
      "schema_version": "1.0",
      "fit_score": 7.5,
      "section_order": ["summary", "education", "skills", "experience", "projects"],
      "summary": { "action": "replace", "text": "<two or three plain-text sentences>" },
      "skills": {
        "action": "replace",
        "content_width": "0.74\\\\textwidth",
        "rows": [
          { "label": "<row label 1>", "items": ["<skill 1a>", "<skill 1b>", "<skill 1c>"] },
          { "label": "<row label 2>", "items": ["<skill 2a>", "<skill 2b>", "<skill 2c>"] },
          { "label": "<row label 3>", "items": ["<skill 3a>", "<skill 3b>", "<skill 3c>"] }
        ]
      },
      "experience": [
        { "id": "<bullet id 1>", "action": "keep", "order": 1, "variant_title": null, "text": null },
        { "id": "<bullet id 2>", "action": "rewrite", "order": 2,
          "variant_title": "<the angle this rewrite takes, 80 characters at most>",
          "text": "<the complete rewritten bullet, in plain text>" },
        { "id": "<bullet id 3>", "action": "drop", "order": null, "variant_title": null, "text": null }
      ],
      "projects": [
        { "id": "<project bullet id>", "action": "keep", "order": 1, "variant_title": null, "text": null }
      ],
      "role_descriptions": [
        { "employment_id": "<employment_id>", "action": "rewrite", "order": null,
          "text": "<the rewritten one-line role description>" }
      ]
    }
    """

    /// JSON Schema (draft 2020-12) for v1.0 — the contract itself. The importer's
    /// `SchemaValidator` enforces the same rules by hand.
    static let schemaJSON = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "urn:applykit:schema:resume-edit-plan:1.0",
      "title": "ApplyKit Resume Edit Plan",
      "type": "object",
      "additionalProperties": false,
      "required": ["schema_version", "fit_score", "section_order", "summary", "skills", "experience", "projects", "role_descriptions"],
      "properties": {
        "schema_version": { "const": "1.0" },
        "fit_score": { "type": "number", "minimum": 0, "maximum": 10 },
        "section_order": {
          "type": "array", "minItems": 1, "maxItems": 5, "uniqueItems": true,
          "items": { "enum": ["summary", "education", "skills", "experience", "projects"] }
        },
        "summary": { "$ref": "#/$defs/summaryEdit" },
        "skills": { "$ref": "#/$defs/skillsEdit" },
        "experience": { "type": "array", "items": { "$ref": "#/$defs/bulletEdit" } },
        "projects": { "type": "array", "items": { "$ref": "#/$defs/bulletEdit" } },
        "role_descriptions": { "type": "array", "items": { "$ref": "#/$defs/roleDescriptionEdit" } }
      },
      "$defs": {
        "summaryEdit": {
          "type": "object",
          "additionalProperties": false,
          "required": ["action", "text"],
          "properties": {
            "action": { "enum": ["keep", "replace", "drop"] },
            "text": { "type": ["string", "null"] }
          },
          "allOf": [
            {
              "if": { "properties": { "action": { "const": "replace" } }, "required": ["action"] },
              "then": { "properties": { "text": { "type": "string", "minLength": 1 } } }
            },
            {
              "if": { "properties": { "action": { "enum": ["keep", "drop"] } }, "required": ["action"] },
              "then": { "properties": { "text": { "type": "null" } } }
            }
          ]
        },
        "roleDescriptionEdit": {
          "type": "object",
          "additionalProperties": false,
          "required": ["employment_id", "action", "order", "text"],
          "properties": {
            "employment_id": { "type": "string", "minLength": 1, "maxLength": 255 },
            "action": { "enum": ["keep", "rewrite", "hide"] },
            "order": { "type": ["integer", "null"], "minimum": 1 },
            "text": { "type": ["string", "null"] }
          },
          "allOf": [
            {
              "if": { "properties": { "action": { "const": "rewrite" } }, "required": ["action"] },
              "then": { "properties": { "text": { "type": "string", "minLength": 1, "maxLength": 500 } } }
            },
            {
              "if": { "properties": { "action": { "const": "keep" } }, "required": ["action"] },
              "then": { "properties": { "text": { "type": "null" } } }
            },
            {
              "if": { "properties": { "action": { "const": "hide" } }, "required": ["action"] },
              "then": { "properties": { "order": { "type": "null" }, "text": { "type": "null" } } }
            }
          ]
        },
        "skillRow": {
          "type": "object",
          "additionalProperties": false,
          "required": ["label", "items"],
          "properties": {
            "label": { "type": "string", "minLength": 1, "maxLength": 40 },
            "items": {
              "type": "array", "minItems": 1, "uniqueItems": true,
              "items": { "type": "string", "minLength": 1, "maxLength": 80 }
            }
          }
        },
        "skillsEdit": {
          "type": "object",
          "additionalProperties": false,
          "required": ["action", "content_width", "rows"],
          "properties": {
            "action": { "const": "replace" },
            "content_width": { "const": "0.74\\\\textwidth" },
            "rows": { "type": "array", "minItems": 3, "maxItems": 3, "items": { "$ref": "#/$defs/skillRow" } }
          }
        },
        "bulletEdit": {
          "type": "object",
          "additionalProperties": false,
          "required": ["id", "action", "order", "variant_title", "text"],
          "properties": {
            "id": { "type": "string", "minLength": 1, "maxLength": 255 },
            "action": { "enum": ["keep", "rewrite", "drop"] },
            "order": { "type": ["integer", "null"], "minimum": 1 },
            "variant_title": { "type": ["string", "null"] },
            "text": { "type": ["string", "null"] }
          },
          "allOf": [
            {
              "if": { "properties": { "action": { "const": "keep" } }, "required": ["action"] },
              "then": {
                "properties": {
                  "order": { "type": "integer", "minimum": 1 },
                  "variant_title": { "type": "null" },
                  "text": { "type": "null" }
                }
              }
            },
            {
              "if": { "properties": { "action": { "const": "rewrite" } }, "required": ["action"] },
              "then": {
                "properties": {
                  "order": { "type": "integer", "minimum": 1 },
                  "variant_title": { "type": "string", "minLength": 1, "maxLength": 80 },
                  "text": { "type": "string", "minLength": 1, "maxLength": 1000 }
                }
              }
            },
            {
              "if": { "properties": { "action": { "const": "drop" } }, "required": ["action"] },
              "then": {
                "properties": {
                  "order": { "type": "null" },
                  "variant_title": { "type": "null" },
                  "text": { "type": "null" }
                }
              }
            }
          ]
        }
      }
    }
    """
}
