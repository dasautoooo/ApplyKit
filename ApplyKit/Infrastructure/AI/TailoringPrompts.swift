//
//  TailoringPrompts.swift
//  ApplyKit
//
//  The Resume Tailor's three prompts — judge (Stage 1), clarify, and build
//  (Stage 2) — plus the rule text they share. The rules are distilled from the
//  `resume-tailor` skill: fit and investment tiers, the 50/30/20 selection
//  weighting, truthfulness, and the Stage 2 output contract.
//
//  All three reference bullets only by the ids in
//  `PromptBuilder.candidateExperiencePool`, so every reply can be applied
//  without guessing which bullet was meant.
//

import Foundation

extension PromptBuilder {

    // MARK: - The skill

    // The rule text is `ResumeTailorSkill`, copied verbatim from the working
    // skill. What follows is only assembly plus the adaptations the app forces.

    /// Who the model is being asked to be, and the rules it may not break.
    static let tailoringIdentity = """
    \(ResumeTailorSkill.identity)

    ## Non-negotiable rules

    \(ResumeTailorSkill.nonNegotiables)
    """

    /// Selection, writing, and truthfulness — `references/tailoring-principles.md`.
    static let tailoringPrinciples = """
    ## Relationship to the master resume

    \(ResumeTailorSkill.principlesMasterResume)

    ## Dual-audience standard

    \(ResumeTailorSkill.principlesDualAudience)

    ## Selection and ordering

    \(ResumeTailorSkill.principlesSelection)

    ## Google-style bullet construction

    \(ResumeTailorSkill.principlesBullets)

    ## Truthful keyword alignment

    \(ResumeTailorSkill.principlesKeywords)

    ## Summary and skills

    \(ResumeTailorSkill.principlesSummarySkills)

    ## Common failure modes

    \(ResumeTailorSkill.principlesFailureModes)
    """

    /// Judging fit, priority, and effort — `references/fit-and-effort.md`.
    ///
    /// One deviation, at the candidate's request: the skill weighs location,
    /// work authorization, and compensation as fit inputs. In the app those are
    /// things the candidate already knows and has already decided, and asking
    /// about them burns one of the three questions, so they are noted as gaps
    /// when the posting makes them hard requirements and are never asked about.
    static let fitAndEffortRules = """
    ## Fit assessment

    \(ResumeTailorSkill.fitAssessment)

    ## Competitiveness and gaps

    \(ResumeTailorSkill.fitCompetitiveness)

    ## Application priority

    \(ResumeTailorSkill.fitPriority)

    ## Tailoring investment

    \(ResumeTailorSkill.fitInvestment)

    ## Weak-investment roles

    \(ResumeTailorSkill.fitWeakInvestment)

    ## Language and uncertainty

    \(ResumeTailorSkill.fitLanguage)

    ## Constraints (ApplyKit)

    Logistics — location, work authorization, work mode, compensation, timing — are the candidate's own \
    business and are already known to them. Note one only when the posting states it as a hard requirement, and \
    only as a gap. Never fold it into the score, and never ask about it.
    """

    /// The fit-assessment half of `fitAndEffortRules`, without the
    /// priority/investment/competitiveness sections that only apply to the
    /// go/no-go decision Stage 1 already made. Used by the PDF check to
    /// re-score fit with the same rubric, against what actually got built.
    static let fitReassessmentRules = """
    \(ResumeTailorSkill.fitAssessment)

    \(ResumeTailorSkill.fitLanguage)

    Logistics — location, work authorization, work mode, compensation, timing — are the candidate's own \
    business and are already known to them. Never fold logistics into the score.
    """

    /// How to write the tailored résumé — SKILL.md's Stage 2 plus the page
    /// budget and explanation rules from `references/output-and-validation.md`.
    static let buildRules = """
    ## Professional summary

    \(ResumeTailorSkill.stageTwoSummary)

    ## Why this summary

    \(ResumeTailorSkill.outputWhyThisSummary)

    ## Skills

    \(ResumeTailorSkill.stageTwoSkills)

    ## Experience and projects

    \(ResumeTailorSkill.stageTwoExperience)

    ## Bullet rewrites

    \(ResumeTailorSkill.stageTwoRewrites)

    ## Explaining each rewrite

    \(ResumeTailorSkill.outputRewriteExplanations)

    ## The ApplyKit LaTeX Skills block

    \(ResumeTailorSkill.outputSkillsBlock)

    ## Page budget

    \(ResumeTailorSkill.outputPageBudget)

    ## Rewrites that would weaken the résumé (ApplyKit)

    - A rewrite must not weaken what it replaces. If the current wording already opens with a verified result, \
    keep a result in the opening — moving it behind a description of what the thing is, is a downgrade, not \
    tailoring. Propose no rewrite at all rather than a worse one.
    - Never drop a verified number, scale, or outcome the current wording states. Adding a different metric does \
    not license removing an existing one; keep both unless the bullet becomes unreadable, and say so if you cut one.
    - Return a rewrite only when its text actually differs from the current wording. Re-stating the bullet \
    unchanged is not a rewrite and will be discarded.
    - The candidate's direction outranks your preferences, but not their credibility: if following it would \
    weaken the résumé, break chronology, or overstate what the evidence supports, do the defensible thing and \
    say plainly in `uncertainties` what you did not do and why.
    """

    /// The skill's pre-delivery checklist, run against the model's own draft.
    static let finalValidation = ResumeTailorSkill.outputValidation

    /// What the skill refuses to do, whatever it is asked.
    static let tailoringBoundaries = ResumeTailorSkill.boundaries

    // MARK: - Shared context blocks

    /// The role being applied to, as the model should see it.
    static func tailoringJobBlock(application: JobApplication) -> String {
        let fields = [
            ("Company", application.companyName),
            ("Title", application.jobTitle),
            ("Location", application.location),
            ("Work mode", application.workModeRaw),
            ("Employment type", application.employmentTypeRaw),
            ("Job URL", application.jobURL),
            ("Candidate's current priority", application.priorityRaw)
        ]
        .filter { !$0.1.trimmed.isEmpty }
        .map { "\($0.0): \($0.1)" }
        .joined(separator: "\n")

        return """
        ## Job
        \(fields)

        ## Job description
        \(application.jobDescription.trimmed.isEmpty ? "None provided." : application.jobDescription)
        """
    }

    /// The master resume the application was built from, when there is one: the
    /// candidate's established specialization identity and starting point.
    static func tailoringCanonicalSourceBlock(masterResume: MasterResume?,
                                              allExperiences: [ExperienceBullet]) -> String {
        guard let masterResume else {
            return """
            ## Canonical source
            No master résumé is applied to this application. Derive the candidate's engineering identity from \
            the strongest, most consistent evidence in the pool below.
            """
        }
        let byID = Dictionary(uniqueKeysWithValues: allExperiences.map { ($0.id, $0) })
        func titles(_ ids: Set<UUID>) -> String {
            let list = ids.compactMap { byID[$0] }
                .map { "[id: \($0.id.uuidString)]" }
                .sorted()
                .joined(separator: ", ")
            return list.isEmpty ? "none" : list
        }
        return """
        ## Canonical source: master résumé "\(masterResume.displayTitle)"
        This is the candidate's established specialization identity and the starting point for this application.
        - Experience bullets it selects: \(titles(masterResume.selectedExperienceIDs))
        - Projects it selects: \(titles(masterResume.selectedProjectIDs))
        - Its summary: \(masterResume.summaryText.trimmed.isEmpty ? "none" : masterResume.summaryText)
        \(masterResume.notes.trimmed.isEmpty ? "" : "- Notes: \(masterResume.notes)")

        Preserve that identity. You may pull any other bullet from the pool when its evidence is genuinely \
        stronger for this role, but do not rebuild the candidate into a different kind of engineer. If this \
        master résumé targets a materially different specialization from the posting, say so plainly in the \
        gaps rather than papering over it.
        """
    }

    /// What the application's résumé currently contains — the baseline any plan edits.
    static func tailoringCurrentStateBlock(application: JobApplication,
                                           employments: [Employment],
                                           globalSkillsBlock: String) -> String {
        let selectedWork = application.selectedExperienceIDs.map(\.uuidString).sorted().joined(separator: ", ")
        let selectedProjects = application.selectedProjectIDs.map(\.uuidString).sorted().joined(separator: ", ")
        let roleLines = employments
            .sorted { $0.displayOrder < $1.displayOrder }
            .compactMap { employment -> String? in
                let text = (application.roleDescription(for: employment.id) ?? employment.roleDescription).trimmed
                guard !text.isEmpty else { return nil }
                let state = application.isRoleDescriptionHidden(for: employment.id) ? "currently HIDDEN" : "currently SHOWN"
                return "- (employment_id: \(employment.id.uuidString)) [\(state)] \(text)"
            }
            .joined(separator: "\n")
        let skills = application.effectiveSkillsBlock(default: globalSkillsBlock)

        return """
        ## Current résumé state (the baseline you are editing)
        - Selected experience ids: \(selectedWork.isEmpty ? "none" : selectedWork)
        - Selected project ids: \(selectedProjects.isEmpty ? "none" : selectedProjects)
        - Section order: \(application.sectionOrder.map(\.rawValue).joined(separator: " → "))
        - Summary: \(application.summaryText.trimmed.isEmpty ? "none" : application.summaryText)
        - Skills block (LaTeX):
        \(skills.trimmed.isEmpty ? "none" : skills)

        ## Role-description lines (per-employment summary line, distinct from bullets)
        \(roleLines.isEmpty ? "None." : roleLines)

        A role-description line is ordered alongside that job's bullets. To place one, put its `employment_id`
        into `ordered_experience_ids` at the position you want — the line then renders after the bullets listed
        before it. Leave the id out to keep the line at the top of its job, where it sits by default.
        """
    }

    /// The public résumé guidance these rules are derived from. The Tech
    /// Interview Handbook is the baseline and can change, so a researching run
    /// re-reads it rather than trusting the distilled copy below.
    static let referenceSources = [
        "https://www.techinterviewhandbook.org/resume/",
        "https://github.com/Paramchoudhary/ResumeSkills/blob/main/skills/resume-tailor/SKILL.md",
        "https://github.com/Paramchoudhary/ResumeSkills/blob/main/skills/tech-resume-optimizer/SKILL.md"
    ]

    /// Research instructions, or the note that this run has no network.
    static func tailoringResearchBlock(application: JobApplication, canResearch: Bool) -> String {
        guard canResearch else {
            return """
            ## Research
            Not available for this run. Work from the job description text above; do not claim facts about the \
            company, the posting, or outside guidance that you cannot support from it.
            """
        }

        let posting = application.jobURL.trimmed.isEmpty
            ? "No posting URL was saved, so work from the job description text above for the role itself."
            : """
              Open \(application.jobURL) and check narrowly:
              - whether the posting is still live;
              - the company's product, customers, and engineering context;
              - role-specific language worth matching truthfully.
              """

        return """
        ## Research
        You can read the web on this run. Use it for two things, and nothing else.

        ### 1. The posting
        \(posting)

        ### 2. The résumé guidance these rules come from
        \(referenceSources.map { "- \($0)" }.joined(separator: "\n"))
        The first is the primary baseline and it changes over time — re-read it and let it correct or sharpen the \
        rules below where they disagree. The other two are secondary workflow references, not authorities.

        Apply their principles; do not treat every preference as universal. These stay fixed no matter what a \
        source says: the two-page budget (the handbook argues for one page — this candidate's cap is two), \
        reverse-chronological employers, no invented facts, no keyword stuffing, no ATS scores or interview \
        predictions, and no requirement that every engineer have a GitHub profile.

        ### Rules for both
        - Record what you find in `research_notes`, each with the URL it came from. Mark anything you inferred \
        rather than sourced with `"inference": true`.
        - If a page refuses to load (403, robots, timeout), search for it instead of giving up, and say so in the \
        note. Never reconstruct a page you could not read — an unread source is simply absent.
        - Keep this brief. A note earns its place only by changing the candidate story, the terminology, or the \
        application judgment.
        """
    }

    // MARK: - Stage 1: judge and propose

    static func tailoringBriefPrompt(application: JobApplication,
                                     allExperiences: [ExperienceBullet],
                                     employments: [Employment],
                                     masterResume: MasterResume?,
                                     globalSkillsBlock: String,
                                     canResearch: Bool) -> String {
        let pool = candidateExperiencePool(allExperiences: allExperiences, employments: employments)
        return """
        \(tailoringIdentity)

        # Stage 1: Judge and propose

        Analyze the role before drafting. Do not write the résumé — that is Stage 2, which runs separately.

        \(ResumeTailorSkill.stageOneWorkflow)

        \(tailoringJobBlock(application: application))

        \(tailoringCanonicalSourceBlock(masterResume: masterResume, allExperiences: allExperiences))

        ## Candidate experience pool (the ONLY valid ids)
        \(pool)

        \(tailoringCurrentStateBlock(application: application, employments: employments, globalSkillsBlock: globalSkillsBlock))

        \(application.notes.trimmed.isEmpty ? "" : "## Candidate notes\n\(application.notes)\n")
        \(tailoringResearchBlock(application: application, canResearch: canResearch))

        ---

        # Judging fit and effort

        \(fitAndEffortRules)

        # Principles

        \(tailoringPrinciples)

        # Boundaries

        \(tailoringBoundaries)

        # Questions

        Questions: ask at most 3, and only about the candidate's technical evidence — what they built, owned, \
        operated, measured, or shipped. A question earns its place only if the answer could change which bullets \
        are selected, how they are worded, or what the résumé can truthfully claim. Tag each one:
        - `fact` — verifies something ambiguous in evidence the candidate already has (ownership, scale, \
        mechanism, the size of a result).
        - `recall` — probes for technical experience the pool does not cover, and must set `gap_id` to the gap it \
        probes. Ask something concrete and answerable from memory, not "do you have any other experience?".

        Never ask about work authorization, visa status or sponsorship, location, relocation, willingness to work \
        onsite/hybrid/remote, salary or compensation, notice period, start date, or how interested the candidate \
        is in the role. The candidate already knows all of it, and no answer to any of it changes a line of the \
        résumé. If the posting makes one a hard requirement, record it as a gap instead.

        Never ask what the job description, pool, or notes already answer.

        Return ONLY this JSON object — no prose, no markdown fences:

        {
          "fit_score": 7.5,
          "fit_confidence": "low | medium | high",
          "recommended_priority": "High | Normal | Low | Skip",
          "investment_tier": "Minimal | Standard | Deep",
          "investment_time": "20–35 minutes",
          "effort_rationale": "<whether more tailoring can change the outcome>",
          "candidate_story": "<the single positioning thesis this résumé should communicate>",
          "strong_matches": [
            { "claim": "<what the candidate can credibly claim>", "evidence": "<the accomplishment behind it>", "experience_id": "<pool id or omit>" }
          ],
          "gaps": [
            { "id": "<short-slug>", "kind": "genuine | presentation | unknown", "text": "<the gap>", "mitigation": "<what to do about it in this application>" }
          ],
          "plan": {
            "summary_direction": "<what the tailored summary should establish>",
            "skills_direction": "<which categories lead, what gets pruned>",
            "selections": [{ "experience_id": "<pool id>", "reason": "<why it earns space>" }],
            "rewrites": [{ "experience_id": "<pool id>", "reason": "<what wording change would help>" }],
            "exclusions": [{ "experience_id": "<pool id>", "reason": "<why it loses its place for THIS role>" }]
          },
          "questions": [
            { "kind": "fact | recall", "gap_id": "<gap id for recall questions, else omit>", "question": "<the question>" }
          ],
          "research_notes": [
            { "claim": "<what you found>", "source_url": "<url>", "inference": false }
          ]
        }

        Rules:
        - Use ONLY ids from the pool. Omit `experience_id` rather than inventing one.
        - Every gap needs a stable `id`; reuse it if you mention the gap elsewhere.
        - Omit `research_notes` entirely when no research was performed.
        - Produce a usable plan even when the recommendation is Low or Skip.
        """
    }

    // MARK: - Clarify loop

    /// One clarify pass: react to answered questions, and — when `probeGaps` is
    /// set — ask fresh recall questions about the genuine gaps.
    static func tailoringClarifyPrompt(brief: TailoringBrief,
                                       answered: [TailoringQuestion],
                                       application: JobApplication,
                                       allExperiences: [ExperienceBullet],
                                       employments: [Employment],
                                       probeGaps: Bool) -> String {
        let pool = candidateExperiencePool(allExperiences: allExperiences, employments: employments)
        let answers = answered.isEmpty
            ? "None yet."
            : answered.map { "- (question_id: \($0.id.uuidString)) [\($0.kind)] Q: \($0.question)\n  A: \($0.answer.trimmed)" }
                .joined(separator: "\n")
        // Everything asked so far, so the model can't re-derive a question it has
        // already put to the candidate.
        let askedLines = brief.questions.isEmpty
            ? "Nothing yet."
            : brief.questions.map { question -> String in
                let state = question.isAnswered ? "answered: \(question.answer.trimmed)" : "not answered yet"
                return "- \(question.question) (\(state))"
            }.joined(separator: "\n")
        let gapLines = brief.gaps.isEmpty
            ? "None recorded."
            : brief.gaps.map { "- (id: \($0.id)) [\($0.kind)] \($0.text)" }.joined(separator: "\n")
        // Probing targets gaps nothing has asked about yet; when they're all
        // covered, the only useful move is sharpening a thin answer.
        let unprobed = brief.unprobedGenuineGaps
        let probeTargets = unprobed.isEmpty
            ? "None — every genuine gap has already been asked about."
            : unprobed.map { "- (id: \($0.id)) \($0.text)" }.joined(separator: "\n")
        let task = probeGaps
            ? """
            Probe for experience the pool does not show, using the gaps listed under "Gaps to probe" below. Ask \
            concrete recall questions a candidate can answer from memory — "have you operated a Kafka pipeline in \
            production?", not "tell me about your data experience". A question is only worth asking if a yes would \
            change what the résumé can claim.

            ## Gaps to probe
            \(probeTargets)

            If that list is empty, or a gap there was already covered by an answer below, ask nothing about it. \
            The one exception: when a previous answer was affirmative but too thin to write a bullet from \
            ("yes, for sure"), ask for the specifics that would make it writable — what you did, where, and what \
            came of it. Never re-ask a yes/no that has already been answered.
            """
            : """
            React to the answers below: update the gaps they resolve or confirm, draft bullets for any real \
            experience they surface, and ask follow-ups only where an answer opened a materially useful thread.
            """

        return """
        You are continuing a résumé tailoring conversation for this candidate. \(task)

        \(tailoringJobBlock(application: application))

        ## Candidate story so far
        \(brief.candidateStory ?? "Not yet established.")

        ## Known gaps
        \(gapLines)

        ## Already asked — never repeat or rephrase any of these
        \(askedLines)

        ## Answers since the last pass
        \(answers)

        ## Candidate experience pool (the ONLY valid ids)
        \(pool)

        ---

        \(tailoringPrinciples)

        Recording what an answer established:
        - Record the fact, not a résumé line. Do not write bullets, do not phrase for a résumé, and do not \
        decide whether it deserves its own bullet — the build stage sees the whole résumé, the page budget, and \
        the writing rules, and makes that call. A fact drafted here in isolation becomes a standalone bullet even \
        when it belongs inside an existing one.
        - Use only what the answer actually states. No invented metrics, scale, ownership, or tooling. If the \
        answer is vague, ask one precise follow-up instead of recording around the vagueness.
        - When the fact belongs with an accomplishment already in the pool, set `related_bullet_id`.
        - Put anything the candidate should double-check before it reaches a résumé in `confirmation_needed`.

        Gaps:
        - When an answer shows the gap was only a presentation problem, change its `kind` to `presentation`.
        - When an answer confirms the candidate genuinely lacks it, keep `kind` as `genuine`, say so in \
        `mitigation`, and stop asking about it.

        Questions:
        - Ask at most 3, and none at all when nothing material is left to learn. Returning an empty \
        `new_questions` list is a correct answer.
        - Ask only about technical evidence: what was built, owned, operated, measured, or shipped. Never about \
        work authorization, visa or sponsorship, location, relocation, onsite/hybrid/remote willingness, salary, \
        notice period, start date, or interest in the role — none of it changes the résumé.
        - Never ask something already listed under "Already asked", in different words or narrower scope. \
        A question is a repeat if the candidate's existing answer would answer it too.
        - A "no" is a settled answer. Confirm the gap and move on; do not look for a way to ask again.
        - Each question must target something no other question covers.

        Return ONLY this JSON object — no prose, no markdown fences:

        {
          "updated_gaps": [
            { "id": "<existing gap id>", "kind": "genuine | presentation | unknown", "text": "<the gap>", "mitigation": "<what to do about it>" }
          ],
          "new_questions": [
            { "kind": "fact | recall", "gap_id": "<gap id, or omit>", "question": "<the question>" }
          ],
          "recalled_facts": [
            {
              "question_id": "<the answered question's id, or omit>",
              "related_bullet_id": "<pool id this belongs with, else null>",
              "fact": "<what the candidate confirmed, in plain terms>",
              "relevance": "<what it proves for this role>",
              "confirmation_needed": "<fact to verify, or omit>"
            }
          ]
        }

        Omit any key you have nothing for. Never invent ids.
        """
    }

    // MARK: - Stage 2: build the plan

    static func tailoringBuildPrompt(brief: TailoringBrief,
                                     application: JobApplication,
                                     allExperiences: [ExperienceBullet],
                                     employments: [Employment],
                                     globalSkillsBlock: String) -> String {
        let pool = candidateExperiencePool(allExperiences: allExperiences, employments: employments)
        let sectionVocab = ResumeSectionKind.defaultOrder.map(\.rawValue).joined(separator: ", ")
        let answers = brief.answeredQuestions.isEmpty
            ? "None."
            : brief.answeredQuestions.map { "- Q: \($0.question)\n  A: \($0.answer.trimmed)" }.joined(separator: "\n")
        let gapLines = brief.gaps.isEmpty
            ? "None recorded."
            : brief.gaps.map { "- [\($0.kind)] \($0.text)\($0.mitigation.map { " — \($0)" } ?? "")" }.joined(separator: "\n")
        let planLines = [
            brief.plan.summaryDirection.map { "- Summary direction: \($0)" },
            brief.plan.skillsDirection.map { "- Skills direction: \($0)" },
            brief.plan.selections.isEmpty ? nil : "- Proposed selections:\n" + brief.plan.selections.map(planItemLine).joined(separator: "\n"),
            brief.plan.rewrites.isEmpty ? nil : "- Proposed rewrites:\n" + brief.plan.rewrites.map(planItemLine).joined(separator: "\n"),
            brief.plan.exclusions.isEmpty ? nil : "- Proposed exclusions:\n" + brief.plan.exclusions.map(planItemLine).joined(separator: "\n")
        ].compactMap { $0 }.joined(separator: "\n")
        let factLines = brief.recalledFacts.isEmpty
            ? "None."
            : brief.recalledFacts.map { fact -> String in
                var line = "- \(fact.fact)"
                if let related = fact.relatedBulletID { line += "\n  belongs with [id: \(related.uuidString)]" }
                if let relevance = fact.relevance?.trimmed, !relevance.isEmpty { line += "\n  relevance: \(relevance)" }
                if let confirm = fact.confirmationNeeded?.trimmed, !confirm.isEmpty { line += "\n  unverified: \(confirm)" }
                return line
            }.joined(separator: "\n")
        let buildNotes = brief.buildNotes.trimmed.isEmpty
            ? "None given. Use your judgement."
            : "\(brief.buildNotes.trimmed)\n\nThis is the candidate's own instruction. Follow it unless it would make the résumé untruthful."
        let skillsTemplate = application.skillsBlockText.trimmed.isEmpty
            ? (globalSkillsBlock.trimmed.isEmpty ? defaultSkillsLatexTemplate : globalSkillsBlock)
            : application.skillsBlockText

        return """
        \(tailoringIdentity)

        # Stage 2: Build the application resume

        Apply the approved direction and any new verified facts. Produce the exact edits ApplyKit should apply, \
        referencing bullets ONLY by the ids in the pool below. ApplyKit holds the résumé itself, so you return \
        the edits rather than a rewritten document.

        \(tailoringJobBlock(application: application))

        ## Approved direction
        - Fit: \(brief.fitScoreText ?? "not scored")\(brief.fitConfidence.map { " (\($0) confidence)" } ?? "")
        - Priority: \(brief.recommendedPriority ?? "unstated") · Investment: \(brief.investmentTier ?? "unstated") \
        \(brief.investmentTime.map { "(\($0))" } ?? "")
        - Candidate story: \(brief.candidateStory ?? "not stated")
        \(planLines.isEmpty ? "" : planLines)

        ## Gaps to respect
        \(gapLines)

        ## Confirmed facts from the candidate's answers
        \(answers)

        ## Facts established during clarification
        \(factLines)
        Decide how each one reaches the résumé, if at all. Prefer folding a fact into an existing bullet — as a \
        `replacement` of the bullet it belongs with — over adding a line. Create a new bullet only when the fact \
        is a distinct accomplishment that carries its own result and cannot strengthen an existing one. A small \
        detail is not a bullet.

        ## The candidate's direction for this build
        \(buildNotes)

        ## Candidate experience pool (the ONLY valid ids)
        \(pool)

        \(tailoringCurrentStateBlock(application: application, employments: employments, globalSkillsBlock: globalSkillsBlock))

        ## Skills LaTeX template to preserve
        Keep this structure, column widths, category-label style, and row syntax exactly; change only which \
        categories and skills appear. Escape LaTeX-sensitive characters in skill text (`&`, `%`, `$`, `#`, `_`, \
        `{`, `}`) without corrupting the template's own commands.

        \(skillsTemplate)

        ---

        # Principles

        \(tailoringPrinciples)

        # Writing the résumé

        \(buildRules)

        # Boundaries

        \(tailoringBoundaries)

        Match the approved direction unless the pool contradicts it; if you deviate, say why in the affected \
        item's reason. Bullets the plan drops are simply absent from the ordered lists — list each one in \
        `drops` with a reason specific to THIS application (redundant signal, weaker evidence, lower relevance, \
        page budget), never a general judgment of the bullet.

        # Final validation

        Before you answer, run this checklist against your own draft and fix what fails. It is internal: it \
        changes what you return, never the shape of it.

        \(finalValidation)

        Return ONLY this JSON object — no prose, no markdown fences. Every field is optional: include one only \
        when you are actually changing it; an omitted field leaves the current value alone.

        {
          "summary": "<tailored professional summary, plain prose>",
          "summary_rationale": [
            { "phrase": "<exact phrase from the summary>", "evidence": "<the accomplishment or confirmed fact behind it>", "signal": "<the posting need it serves>", "why_it_earns_space": "<hiring value and trade-off>" }
          ],
          "deliberately_omitted": "<the strongest emphasis you left out of the summary, and why another signal was worth more>",
          "skills_latex": "<the tailored Skills block, raw LaTeX using the template above>",
          "section_order": ["<from: \(sectionVocab)>"],
          "ordered_experience_ids": ["<work bullet ids, in final résumé order>"],
          "ordered_project_ids": ["<project ids, in final résumé order>"],
          "replacements": [
            {
              "experience_id": "<pool id>",
              "text": "<tailored bullet text>",
              "name": "<short variant label, e.g. the company or angle>",
              "reason": "<the hiring value of this rewrite — not 'matches the JD'>",
              "signal": "Relevance | Technical depth | Impact | Clarity | ATS terminology | Concision | Ownership",
              "confirmation_needed": "<fact to verify before submitting, or omit>"
            }
          ],
          "new_bullets": [
            {
              "text": "<the bullet, following the writing rules above>",
              "employment_id": "<the employment it belongs under, from the pool headers, or omit>",
              "reason": "<why it earns a line of its own rather than strengthening an existing bullet>",
              "confirmation_needed": "<fact to verify before submitting, or omit>"
            }
          ],
          "drops": [
            { "experience_id": "<pool id>", "reason": "<why it loses its place for this role>" }
          ],
          "role_descriptions": [
            { "employment_id": "<employment id>", "include": true, "text": "<tailored role line, or omit>" }
          ],
          "readiness": "Ready to submit | Ready after minor corrections | Needs factual confirmation | Needs layout verification",
          "uncertainties": ["<facts that still need confirming before submitting>"]
        }

        Rules:
        - Use ONLY ids from the pool. Drop anything you cannot confidently match rather than guessing.
        - `ordered_experience_ids` and `ordered_project_ids` are the FINAL selected sets, in order.
        - A rewritten bullet must also appear in the appropriate ordered list so it stays selected.
        - Cover every meaningful phrase of the summary in `summary_rationale`, not just the obvious keywords.
        - `new_bullets` is for confirmed facts that genuinely stand alone. Every one of them follows the same \
        writing rules as the rest — impact-first where there is a result, the mechanism that makes it credible, \
        and nothing the facts above do not support. Leave it out entirely when nothing qualifies.
        - Set `role_descriptions[].include` only when the line's visibility changes, and `text` only when its \
        wording changes.
        - Length is an estimate until rendered; say so in `uncertainties` if the two-page fit is tight.
        """
    }

    // MARK: - Reviewing the rendered résumé

    /// The skill's closing step: with a rendered PDF in hand, stop estimating.
    ///
    /// Page count comes from the file, so the reviewer is asked to judge against
    /// it rather than guess at it. The text is what the PDF actually yields —
    /// the same thing an ATS would extract — so problems that only exist after
    /// rendering (wrapping, orphaned headings, lost reading order) are visible.
    static func tailoringReviewPrompt(application: JobApplication,
                                      brief: TailoringBrief?,
                                      rendered: ResumePDFInspector.Rendered,
                                      renderedExperiences: [ExperienceBullet],
                                      employments: [Employment],
                                      globalSkillsBlock: String) -> String {
        let pool = candidateExperiencePool(allExperiences: renderedExperiences, employments: employments)
        let story = brief?.candidateStory?.trimmed
        let uncertainties = brief?.recalledFacts
            .compactMap { $0.confirmationNeeded?.trimmed }
            .filter { !$0.isEmpty } ?? []

        return """
        \(tailoringIdentity)

        # Reviewing the rendered résumé

        The résumé has been generated. Review the actual file — this is the check the skill defers until a \
        render exists, so nothing here is an estimate.

        ## The role
        \(application.companyName) — \(application.jobTitle)

        ## The candidate story this résumé is meant to carry
        \(story?.isEmpty == false ? story! : "Not recorded.")

        \(brief?.fitScoreText.map { "## Stage 1's fit judgment (for reference only — re-score from what actually got built, not from this)\nFit: \($0)\(brief?.fitConfidence.map { " (\($0) confidence)" } ?? "")\n" } ?? "")
        ## Measured from the file
        - Pages: \(rendered.pageCount)
        - Text extraction: \(rendered.isTextEmpty
            ? "produced NO text at all — treat this as a blocking ATS failure"
            : "produced text, reproduced below with its page breaks")

        \(uncertainties.isEmpty ? "" : "## Facts the candidate has not yet confirmed\n" + uncertainties.map { "- \($0)" }.joined(separator: "\n"))

        ## Extracted text
        \(rendered.text)

        ## What is on this résumé (the ONLY valid ids)
        These are the bullets the document actually contains. Bullets the candidate has not selected are not \
        listed and are not yours to touch: choosing what belongs on the résumé happened in the build, and this \
        is a check on the artifact.

        \(pool)

        \(tailoringCurrentStateBlock(application: application, employments: employments, globalSkillsBlock: globalSkillsBlock))

        ---

        # Page-budget guidance

        \(ResumeTailorSkill.outputPageBudget)

        # Principles

        \(tailoringPrinciples)

        # Writing the résumé

        Any edit you propose is a résumé edit, held to the same rules as the ones the build produced — a
        tightened bullet still leads with its result, a replacement Skills block still uses the structure below,
        and nothing you write may claim more than the evidence supports.

        \(buildRules)

        # Boundaries

        \(tailoringBoundaries)

        # Final validation

        \(ResumeTailorSkill.outputValidation)

        # Re-judging fit

        The build can drift from what Stage 1 judged — a rewrite came out softer, a bullet got cut for space, \
        wording lost precision. Score fit again from what this rendered document actually claims, using the same \
        rubric Stage 1 used:

        \(fitReassessmentRules)

        ---

        Judge only what the rendered file can show you. You cannot see fonts, margins, or colour, so do not \
        comment on them; you can see length, ordering, wrapping, repetition, missing or duplicated sections, \
        and whether the extracted text reads in a sensible order. Do not re-litigate content choices that are \
        defensible — this is a check on the artifact, not a second tailoring pass.

        Where a finding can be fixed by changing résumé content, also express it as an edit in `edits`, using the \
        ids above — and only those ids. You may tighten, drop, or reorder what is on the résumé; you may not add \
        material that is not.

        A role-description line — the scope sentence under a job — is often what pushes a heading away from its \
        bullets or a résumé past its page budget. Hiding one (`include: false`) or tightening its wording is a \
        legitimate fix, subject to the same rule as the build: keep it only when it supplies product, system, \
        team, or scale context the bullets cannot carry cleanly. That is what makes a finding actionable rather than a note to self: duplicated \
        content, an over-long bullet, a section that needs reordering, or a Skills block that extracts badly all \
        have edits. Pure layout or extraction observations usually do not — leave `edits` out entirely when \
        nothing can be fixed by changing content.

        Return ONLY this JSON object — no prose, no markdown fences:

        {
          "checks": [
            {
              "section": "<the checklist section it came from>",
              "question": "<the checklist question, worded as the skill words it>",
              "status": "pass | fail | unclear",
              "note": "<the evidence in the rendered document, or why it is unclear>"
            }
          ],
          "fit_score": 7.5,
          "fit_confidence": "low | medium | high",
          "verdict": "Ready to submit | Ready after minor corrections | Needs factual confirmation | Needs layout verification",
          "extraction_note": "<what the extracted text says about ATS readability, one line>",
          "findings": [
            {
              "severity": "blocker | fix | note",
              "text": "<what is wrong, specific enough to find in the document>",
              "fix": "<what to change, or omit when there is nothing to do>"
            }
          ],
          "edits": {
            "summary": "<replacement summary, or omit>",
            "skills_latex": "<replacement Skills block, or omit>",
            "ordered_experience_ids": ["<work bullet ids, in final order>"],
            "ordered_project_ids": ["<project ids, in final order>"],
            "replacements": [
              { "experience_id": "<pool id>", "text": "<tightened bullet>", "name": "<short label>",
                "reason": "<which finding this resolves>", "signal": "Concision | Clarity | Relevance | Impact | Technical depth | ATS terminology | Ownership" }
            ],
            "drops": [{ "experience_id": "<pool id>", "reason": "<which finding this resolves>" }],
            "role_descriptions": [
              { "employment_id": "<employment id>", "include": false,
                "text": "<tighter wording, or omit to only change visibility>" }
            ]
          }
        }

        Rules:
        - `checks` is the Final validation checklist above, run against this rendered document. Work through it \
        and report every question you can actually answer from the file, quoting the question as the checklist \
        words it. Mark `pass`, `fail`, or `unclear`, and put the evidence in `note`. Omit questions the rendered \
        document cannot answer — the ones about how long the work took, or about facts only the candidate can \
        confirm — rather than guessing at them. An honest `unclear` is worth more than a confident guess.
        - `fit_score` and `fit_confidence` are the fit re-check above — judge them from what this rendered \
        document actually says, not from the brief's earlier score or the plan that produced it. A résumé that \
        lost its strongest evidence to a page-budget cut should score lower here than Stage 1 scored the plan.
        - In `findings`, name a bullet by its opening words, not by its id — these sentences are read by a person. \
        Ids belong in `edits`, where they are applied by machine.
        - `blocker` means do not submit it like this: over the two-page cap, a section missing, text that does \
        not extract, content in an order a reader or parser would misread.
        - `fix` is worth correcting before sending. `note` is an observation and nothing more.
        - Return an empty `findings` list when the document is sound. Do not invent problems to look thorough.
        - Never suggest shrinking margins, spacing, or font size to fit the page budget — cut content in the \
        order the guidance above gives.
        """
    }

    /// Last-resort second pass when a reply didn't parse: hand the raw text back
    /// and ask only for the JSON, carrying nothing new in. Cheaper and more
    /// faithful than re-running the whole judgment, and it costs one short call
    /// rather than losing the work.
    static func jsonRepairPrompt(rawReply: String, schema: String) -> String {
        """
        The text below was supposed to be a single JSON object matching a schema, but it could not be parsed.
        Extract what is genuinely there and return it as valid JSON.

        ## Required schema
        \(schema)

        ## Text to convert
        \(rawReply)

        ---

        Rules:
        - Return ONLY the JSON object. No prose, no markdown fences, no trailing commentary.
        - Carry over only what the text actually says. Do not add, infer, or invent content, ids, or scores.
        - Drop any field the text does not cover rather than filling it with a placeholder.
        - Fix structural problems only: unquoted keys, trailing commas, comments, single quotes, \
        unescaped newlines inside strings, truncated tails.
        """
    }

    /// The brief's shape, for the repair pass.
    static let briefSchemaSummary = """
    {
      "fit_score": 7.5,
      "fit_confidence": "low | medium | high",
      "recommended_priority": "High | Normal | Low | Skip",
      "investment_tier": "Minimal | Standard | Deep",
      "investment_time": "20–35 minutes",
      "effort_rationale": "...",
      "candidate_story": "...",
      "strong_matches": [{ "claim": "...", "evidence": "...", "experience_id": "<uuid>" }],
      "gaps": [{ "id": "<slug>", "kind": "genuine | presentation | unknown", "text": "...", "mitigation": "..." }],
      "plan": {
        "summary_direction": "...", "skills_direction": "...",
        "selections": [{ "experience_id": "<uuid>", "reason": "..." }],
        "rewrites": [{ "experience_id": "<uuid>", "reason": "..." }],
        "exclusions": [{ "experience_id": "<uuid>", "reason": "..." }]
      },
      "questions": [{ "kind": "fact | recall", "gap_id": "<gap id>", "question": "..." }],
      "research_notes": [{ "claim": "...", "source_url": "...", "inference": false }]
    }
    """

    /// The plan's shape, for the repair pass.
    static let planSchemaSummary = """
    {
      "summary": "...",
      "summary_rationale": [{ "phrase": "...", "evidence": "...", "signal": "...", "why_it_earns_space": "..." }],
      "deliberately_omitted": "...",
      "skills_latex": "...",
      "section_order": ["Summary", "Education", "Experience", "Selected Projects", "Skills"],
      "ordered_experience_ids": ["<uuid>"],
      "ordered_project_ids": ["<uuid>"],
      "replacements": [{ "experience_id": "<uuid>", "text": "...", "name": "...", "reason": "...", "signal": "...", "confirmation_needed": "..." }],
      "new_bullets": [{ "text": "...", "employment_id": "<uuid>", "reason": "...", "confirmation_needed": "..." }],
      "drops": [{ "experience_id": "<uuid>", "reason": "..." }],
      "role_descriptions": [{ "employment_id": "<uuid>", "include": true, "text": "..." }],
      "readiness": "Ready to submit | Ready after minor corrections | Needs factual confirmation | Needs layout verification",
      "uncertainties": ["..."]
    }
    """

    /// The review's shape, for the repair pass.
    static let reviewSchemaSummary = """
    {
      "checks": [{ "section": "...", "question": "...", "status": "pass | fail | unclear", "note": "..." }],
      "fit_score": 7.5,
      "fit_confidence": "low | medium | high",
      "verdict": "Ready to submit | Ready after minor corrections | Needs factual confirmation | Needs layout verification",
      "extraction_note": "...",
      "findings": [{ "severity": "blocker | fix | note", "text": "...", "fix": "..." }]
    }
    """

    /// The clarify pass's shape, for the repair pass.
    static let clarificationSchemaSummary = """
    {
      "updated_gaps": [{ "id": "<gap id>", "kind": "genuine | presentation | unknown", "text": "...", "mitigation": "..." }],
      "new_questions": [{ "kind": "fact | recall", "gap_id": "<gap id>", "question": "..." }],
      "recalled_facts": [{ "question_id": "<uuid>", "related_bullet_id": "<uuid or null>", "fact": "...", "relevance": "...", "confirmation_needed": "..." }]
    }
    """

    /// Fallback Skills structure when neither the application nor the profile has
    /// one yet (matches the skill's documented default).
    static let defaultSkillsLatexTemplate = """
    \\begin{tabular}{@{} >{\\bfseries}l @{\\hspace{2ex}} >{\\raggedright\\arraybackslash}p{0.72\\textwidth}}
      \\textbf{Languages:} & Swift, Objective-C, Python \\\\
      \\textbf{Apple frameworks:} & UIKit, SwiftUI, Combine \\\\
    \\end{tabular}
    """

    private static func planItemLine(_ item: TailoringBrief.ProposedPlan.Item) -> String {
        let reference = item.experienceID.map { "[id: \($0.uuidString)]" } ?? (item.label ?? "(unspecified)")
        return "  - \(reference)\(item.reason.map { " — \($0)" } ?? "")"
    }
}
