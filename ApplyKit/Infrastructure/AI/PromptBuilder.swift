import Foundation

enum PromptBuilder {
    static func prompt(for application: JobApplication, purpose: PromptPurpose,
                       template: PromptTemplate?, selectedExperiences: [ExperienceBullet]) -> String {
        let base = template?.templateText ?? fallbackTemplate(for: purpose)
        let experienceBlock = selectedExperiences.isEmpty
            ? "No experience items selected. Do not infer or invent experience."
            : selectedExperiences.map { $0.promptSummary(variantID: application.selectedVariantID(for: $0.id)) }.joined(separator: "\n\n")
        var prompt = base
        [("{{company}}", application.companyName), ("{{job_title}}", application.jobTitle),
         ("{{location}}", application.location), ("{{job_url}}", application.jobURL),
         ("{{job_description}}", application.jobDescription), ("{{experience_items}}", experienceBlock),
         ("{{notes}}", application.notes)].forEach { prompt = prompt.replacingOccurrences(of: $0.0, with: $0.1) }
        return prompt + "\n\nGlobal rule: Do not invent experience, employers, dates, education, credentials, skills, projects, responsibilities, or metrics. If a claim is not in the selected experience source of truth, say it is not supported."
    }

    private static func fallbackTemplate(for purpose: PromptPurpose) -> String {
        "Purpose: \(purpose.rawValue)\n\nCompany: {{company}}\nJob title: {{job_title}}\n\nJob description:\n{{job_description}}\n\nSelected experience source of truth:\n{{experience_items}}"
    }

    static func experienceRecommendationPrompt(application: JobApplication, allExperiences: [ExperienceBullet]) -> String {
        let catalogue = allExperiences.map { exp in
            "ID: \(exp.id.uuidString)\nTitle: \(exp.displayTitle)\nCompany: \(exp.company) \(exp.role)\nSkills: \(exp.skillsText)\nBullet: \(exp.bulletText.prefix(200))"
        }.joined(separator: "\n---\n")
        return """
        You are a resume advisor. Given the job description below, select the 4–8 most relevant experience bullets from the catalogue.

        Job: \(application.companyName) — \(application.jobTitle)
        Location: \(application.location)

        Job Description:
        \(application.jobDescription)

        Experience Catalogue:
        \(catalogue)

        Return ONLY a JSON object in this exact format, no other text:
        {"recommended_ids": ["<UUID>", "<UUID>", ...]}

        Rules:
        - Use the exact UUID strings from the catalogue.
        - Prefer high-impact and skill-matched bullets.
        - Do not invent or modify any IDs.
        """
    }

    static func bulletRefinementPrompt(application: JobApplication, experience: ExperienceBullet) -> String {
        """
        You are a resume writer. Rewrite the bullet point below to better match the job description while remaining completely truthful to the original content. Do not add metrics, claims, or skills not present in the original.

        Job: \(application.companyName) — \(application.jobTitle)

        Job Description:
        \(application.jobDescription)

        Original bullet:
        \(experience.bulletText)

        Return ONLY the rewritten bullet text. No explanation, no quotes, no markdown, no leading dash or bullet character.
        """
    }

    static func coverLetterPrompt(
        application: JobApplication,
        selectedExperiences: [ExperienceBullet],
        selectedProjects: [ExperienceBullet],
        employments: [Employment]
    ) -> String {
        let experienceBlock = (selectedExperiences + selectedProjects).isEmpty
            ? "No experience items selected. Do not invent or infer experience."
            : (selectedExperiences + selectedProjects)
                .map { $0.promptSummary(variantID: application.selectedVariantID(for: $0.id)) }
                .joined(separator: "\n\n")
        let employmentBlock = employments
            .map { "- \($0.companyName), \($0.role), \($0.dateRangeText())" }
            .joined(separator: "\n")

        return """
        You are writing a truthful, concise cover letter for Leonard Chen.
        The style should be plain, direct, and easy to skim. Write at an undergraduate reading level.

        Return ONLY a JSON object. Do not wrap it in markdown. Do not include explanations.
        ApplyKit will insert your content into a LaTeX template, so do not return LaTeX commands or a full LaTeX document.

        Hard rules:
        - Do not invent employers, projects, dates, credentials, skills, metrics, or accomplishments.
        - Use only the job description, selected experience source of truth, employment history, and notes.
        - If a requirement is not supported by the selected source material, do not claim it.
        - Keep the letter to 3-4 focused paragraphs.
        - Use simple wording. Avoid inflated language, sales language, clichés, and vague enthusiasm.
        - Prefer concrete matches: job need -> relevant experience -> how it helps.
        - Make each paragraph easy to skim, with one clear point.
        - Do not use phrases like "I am thrilled", "I am passionate", "dynamic team", "proven track record", "leverage", or "cutting-edge".
        - Sound professional, calm, and human. Do not sound like marketing copy.
        - Return plain text. Do not escape LaTeX special characters; ApplyKit will escape them.

        Return this exact JSON shape:
        {
          "recipient_lines": ["Hiring Manager", "\(application.companyName.trimmed.isEmpty ? "Company" : application.companyName)"],
          "salutation": "Dear Hiring Manager,",
          "paragraphs": ["paragraph one", "paragraph two", "paragraph three"],
          "closing": "Sincerely,"
        }

        ## Application
        Company: \(application.companyName)
        Job title: \(application.jobTitle)
        Location: \(application.location)
        Job URL: \(application.jobURL)

        ## Job Description
        \(application.jobDescription.trimmed.isEmpty ? "No job description provided." : application.jobDescription)

        ## Application Notes
        \(application.notes.trimmed.isEmpty ? "No notes provided." : application.notes)

        ## Employment History
        \(employmentBlock.trimmed.isEmpty ? "No employment history provided." : employmentBlock)

        ## Selected Experience Source Of Truth
        \(experienceBlock)
        """
    }

    /// Growth suggestions: bullets the candidate could *develop* to close this
    /// role's gaps. When a tailoring brief exists it supplies the gaps and the
    /// candidate story, so this stops re-deriving them from the job description.
    static func bulletCurationPrompt(application: JobApplication, allExperiences: [ExperienceBullet],
                                     employments: [Employment], brief: TailoringBrief? = nil) -> String {
        let experienceLines = allExperiences.map { exp in
            "ID: \(exp.id.uuidString)\n  • \(exp.displayTitle) @ \(exp.company.isEmpty ? "Personal" : exp.company)\(exp.role.isEmpty ? "" : " / \(exp.role)") — \(exp.bulletText.prefix(200)) [Skills: \(exp.skillsText)]"
        }.joined(separator: "\n")
        let employmentLines = employments.map { "• \($0.companyName) | \($0.role) | \($0.dateRangeText())" }.joined(separator: "\n")
        let briefBlock: String = {
            guard let brief else { return "" }
            let gaps = brief.gaps
                .filter { $0.gapKind != .presentation }
                .map { "- [\($0.kind)] \($0.text)\($0.mitigation.map { " — \($0)" } ?? "")" }
                .joined(separator: "\n")
            guard !gaps.isEmpty || brief.candidateStory != nil else { return "" }
            return """

            ## Tailoring Brief (target these, do not re-derive them)
            \(brief.candidateStory.map { "Candidate story: \($0)" } ?? "")
            Gaps this role exposes:
            \(gaps.isEmpty ? "None recorded." : gaps)

            Aim every suggestion at one of these gaps. Skip a gap the candidate cannot credibly bridge from \
            their existing skills.
            """
        }()
        return """
        You are a career advisor helping a candidate build a strong resume for a specific role.
        \(briefBlock)
        Context:
        - The experience bullets below are from the candidate's experience bank — a catalogue of past work. They are NOT the current resume.
        - Produce two types of suggestions:
          1. REWRITES: Take an existing bullet and reframe it to better match this role — same underlying story, but different angle, emphasis, tech stack, or scope. These should feel like a natural evolution of what already exists.
          2. NEW BULLETS: Entirely new experience bullets the candidate could develop, grounded in existing skills as a bridge. Do not suggest unrelated skills.
        - For rewrites, set "source_bullet_id" to the exact UUID of the bullet being rewritten.
        - For new bullets, omit "source_bullet_id" (or set it to null).
        - Do not invent metrics. Write bullets that are ready to be filled in once the candidate gains or frames the experience.

        ## Job
        Company: \(application.companyName)
        Title: \(application.jobTitle)
        Location: \(application.location)

        ## Job Description
        \(application.jobDescription)

        ## Employment History
        \(employmentLines.isEmpty ? "None provided." : employmentLines)

        ## Experience Bank (with IDs)
        \(experienceLines.isEmpty ? "None provided." : experienceLines)

        ---

        Generate 5–9 total suggestions (mix of rewrites and new bullets). For each:
        - bullet: A strong, resume-ready bullet point. Start with an action verb.
        - relevance: For rewrites — what changed and why this framing fits the role better. For new bullets — which existing experience this extends from.
        - how_to_learn: Concrete, actionable steps (courses, projects, practice) to genuinely own this.
        - story: A short narrative (2–4 sentences) the candidate can tell in interviews to authentically claim this experience.
        - source_bullet_id: The UUID string of the bullet being rewritten, or null for new bullets.

        Return ONLY a valid JSON array, no other text:
        [
          {
            "bullet": "...",
            "relevance": "...",
            "how_to_learn": "...",
            "story": "...",
            "source_bullet_id": "<UUID or null>"
          }
        ]
        """
    }

    static func parseCuratedSuggestions(from response: String, allExperiences: [ExperienceBullet]) -> [CuratedBulletSuggestion] {
        guard let startIdx = response.firstIndex(of: "["),
              let endIdx = response.lastIndex(of: "]") else { return [] }
        let jsonString = String(response[startIdx...endIdx])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let experienceIndex = Dictionary(uniqueKeysWithValues: allExperiences.map { ($0.id, $0) })
        return array.compactMap { dict in
            guard let bullet = dict["bullet"] as? String, !bullet.trimmed.isEmpty else { return nil }
            let sourceID: UUID? = (dict["source_bullet_id"] as? String).flatMap { UUID(uuidString: $0) }
            let sourceTitle = sourceID.flatMap { experienceIndex[$0]?.displayTitle }
            return CuratedBulletSuggestion(
                bulletText: bullet,
                relevance: dict["relevance"] as? String ?? "",
                howToLearn: dict["how_to_learn"] as? String ?? "",
                story: dict["story"] as? String ?? "",
                sourceBulletID: sourceID,
                sourceBulletTitle: sourceTitle
            )
        }
    }

    static func parseRecommendedIDs(from response: String, validIDs: Set<UUID>) -> [UUID] {
        guard let jsonRange = response.range(of: "\\{[^}]*\\}", options: .regularExpression),
              let data = String(response[jsonRange]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawIDs = json["recommended_ids"] as? [String] else { return [] }
        return rawIDs.compactMap { UUID(uuidString: $0) }.filter { validIDs.contains($0) }
    }

    /// Turns a pasted ChatGPT tailoring suggestion (freeform prose, possibly with
    /// truncated `"…"` quotes) into a strict `TailoringPlan` JSON object keyed by
    /// the application's real bullet UUIDs. The candidate pool below carries those
    /// UUIDs so the model can resolve quotes to ids; anything not addressable by a
    /// provided id must be dropped rather than invented.
    /// A flat listing of every selectable bullet with its real UUID, grouped by
    /// employment (then Projects, then Unassigned). Shared by the tailoring
    /// prompts so every reply references exact ids.
    static func candidateExperiencePool(allExperiences: [ExperienceBullet],
                                        employments: [Employment]) -> String {
        let employmentsByID = Dictionary(uniqueKeysWithValues: employments.map { ($0.id, $0) })

        func isProject(_ exp: ExperienceBullet) -> Bool {
            if exp.isProjectLike { return true }
            if let id = exp.employmentID, let emp = employmentsByID[id] {
                return emp.experienceCategory == .project || emp.experienceCategory == .openSource
            }
            return false
        }

        func bulletLine(_ exp: ExperienceBullet) -> String {
            var line = "- [id: \(exp.id.uuidString)] \(exp.bulletText.trimmed)"
            let variants = exp.variations
            if !variants.isEmpty {
                let vs = variants.map { "\($0.id.uuidString) (\"\($0.displayName)\")" }.joined(separator: ", ")
                line += "\n    existing variants: \(vs)"
            }
            return line
        }

        let workExperiences = allExperiences.filter { !isProject($0) }
        let projectExperiences = allExperiences.filter { isProject($0) }

        var poolBlocks: [String] = []
        for employment in employments.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            let bullets = workExperiences.filter { $0.employmentID == employment.id }
            guard !bullets.isEmpty else { continue }
            let header = "### \(employment.summaryLine) (employment_id: \(employment.id.uuidString))"
            poolBlocks.append(([header] + bullets.map(bulletLine)).joined(separator: "\n"))
        }
        let unassignedWork = workExperiences.filter { $0.employmentID == nil || employmentsByID[$0.employmentID!] == nil }
        if !unassignedWork.isEmpty {
            poolBlocks.append((["### Unassigned experience"] + unassignedWork.map(bulletLine)).joined(separator: "\n"))
        }
        if !projectExperiences.isEmpty {
            let lines = projectExperiences.map { exp -> String in
                let title = exp.resumeDisplayName.trimmed.isEmpty ? exp.displayTitle : exp.resumeDisplayName
                return "- [id: \(exp.id.uuidString)] (\(title)) \(exp.bulletText.trimmed)"
            }
            poolBlocks.append((["### Projects"] + lines).joined(separator: "\n"))
        }
        return poolBlocks.isEmpty ? "None." : poolBlocks.joined(separator: "\n\n")
    }

    /// Converts a PDF review pasted from ChatGPT into the same `TailoringReview`
    /// the in-app check produces, so both routes land in one panel.
    ///
    /// Transcription only: the judgment is the pasted reviewer's, and page count comes from the file rather than
    /// from either model.
    static func reviewReconciliationPrompt(pastedReview: String,
                                           application: JobApplication,
                                           renderedExperiences: [ExperienceBullet],
                                           employments: [Employment]) -> String {
        let pool = candidateExperiencePool(allExperiences: renderedExperiences, employments: employments)
        return """
        You are a precise data-transformation tool for the ApplyKit résumé builder. Convert the pasted review of a \
        rendered résumé into a single JSON object. You are transcribing someone else's review: never judge the \
        résumé yourself, and never soften, sharpen, or add to what it says.

        ## The role
        \(application.companyName) — \(application.jobTitle)

        ## What is on this résumé (the ONLY valid ids)
        \(pool)

        ## Pasted review
        \(pastedReview)

        ---

        Produce JSON with this schema. Every field is OPTIONAL — include a field ONLY when the review states it.

        {
          "fit_score": <the review's score out of 10, if it gives one>,
          "fit_confidence": "<low | medium | high, if stated>",
          "verdict": "<Ready to submit | Ready after minor corrections | Needs factual confirmation | Needs layout verification>",
          "extraction_note": "<what it says about how the text extracts, one line>",
          "checks": [
            { "section": "<the part of its checklist this came from>", "question": "<the question it answered>",
              "status": "pass | fail | unclear", "note": "<its evidence>" }
          ],
          "findings": [
            { "severity": "blocker | fix | note", "text": "<what it says is wrong>", "fix": "<what it says to do, or omit>" }
          ],
          "edits": {
            "summary": "<replacement summary it gives, or omit>",
            "skills_latex": "<replacement Skills block, or omit>",
            "ordered_experience_ids": ["<bullet ids in the order it asks for>"],
            "replacements": [
              { "experience_id": "<pool id>", "text": "<the replacement wording it gives>", "name": "<short label>",
                "reason": "<its reason>", "signal": "<exactly one of: Relevance, Technical depth, Impact, Clarity, ATS terminology, Concision, Ownership>" }
            ],
            "drops": [{ "experience_id": "<pool id>", "reason": "<its reason>" }],
            "role_descriptions": [{ "employment_id": "<employment id>", "include": false, "text": "<tighter wording, or omit>" }]
          }
        }

        Rules:
        - `edits` carries across only wording the review actually supplies. A finding it describes but gives no \
        replacement text for belongs in `findings` alone — do not write the fix yourself.
        - Use ONLY ids from the pool above. If the review names a bullet you cannot confidently match to one, \
        leave it out of `edits` rather than guessing, and let the finding carry it.
        - Do not transcribe page count: ApplyKit measures that from the file.
        - Do NOT invent checks, findings, scores, or ids.

        Return ONLY the JSON object — no prose, no markdown fences.
        """
    }
}
