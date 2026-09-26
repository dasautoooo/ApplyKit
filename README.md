# ApplyKit

Native macOS app (SwiftUI) for job application management. It tracks applications through the interview pipeline, polls company job boards for new postings, keeps a reusable bank of experience bullets, and renders per-application LaTeX resumes and cover letters. Resume tailoring runs in one of two ways: in an external chat (ChatGPT, Claude), whose JSON edit plan ApplyKit validates and applies deterministically, or through the Claude Code or Codex CLI run as a subprocess. All data is plain YAML, Markdown, and JSON in a local workspace directory.

## Sections

The sidebar has six sections.

**Applications**: one record per job application. The editor holds:
- Role details, status, priority, and the job description. Status changes, archive/restore, and manual notes are recorded on a per-application timeline.
- Interview Process: the recruiter screen and each interview round, one row per step showing its result and time; click a row to edit it. A step has a type, a result, logistics (time, duration, format, meeting link or address, interviewers), a prep checklist and notes, and a debrief (1–5 rating, questions asked, notes). Rounds are numbered in date order, and the screen isn't counted as one. A new step starts as Scheduling and becomes Scheduled once it has a time.
- Resume content: selected bullets and variants, their order, section order, summary, skills block, role-description overrides, and page layout (font size, margins). See [Resume content model](#resume-content-model).
- Documents: generate the resume (LaTeX → PDF) and draft a cover letter.
- The Resume Tailor (see [Resume Tailor](#resume-tailor)).
- Applications can be created from a job-posting URL. ApplyKit reads the posting through the ATS API when it recognizes the host, or renders the page in an offscreen `WKWebView`, extracts the role details with the AI backend, and starts the resume from the best-matching master resume. Applications can also be duplicated and archived.

Status pipeline: `Saved → Interested → Preparing → Applied → Referral Requested → Recruiter Screen → Interviewing → Offer / Rejected / Ghosted / Withdrawn`

Recruiter Screen and Interviewing follow the Interview Process. Logging a screen moves the status to Recruiter Screen, and logging a round moves it to Interviewing. Deleting steps moves it back, and deleting the last one restores the status from before. Picking either status adds the missing step. Offer, Rejected, Ghosted and Withdrawn never change automatically, and a step marked Didn't Advance offers to set Rejected. The steps are the timeline's record of this phase, so moves into it aren't logged as separate status changes. Older workspaces load `Technical Interview` and `Final Interview` as Interviewing, and their timelines keep the old names.

**Insights**: how applications move through the pipeline, computed live from the workspace. KPI tiles (applied, response, interview, and offer rates, median days to a reply) over a stage funnel, a Sankey flow, the current pipeline, weekly activity, time to response, and fit score vs outcome. The whole dashboard (toolbar Share) or any single chart (the card's share button) can be shared through the system share menu, copied, or saved as PNG or PDF; exports render light on white.
- Applied: has an applied date, an Applied status in its history, or a later stage (Rejected and Ghosted included). Saved, or withdrawn before applying, doesn't count.
- Stages run Applied → Screen → Round 1–4+ → Offer. Reaching a stage counts every stage before it, and Offer can follow any round.
- Archived applications count, since rejections usually get archived.
- A step still in Scheduling counts toward reach only if it's a screen, and never toward dates. History reconstructed for older applications counts toward reach but not toward durations.
- The date range filters by applied date, or saved date if never applied. Refresh (⌘R) re-anchors "now".

**Discover**: tracks company job boards and collects new postings into an inbox.
- Providers: Greenhouse, Lever, Ashby, Workday, SmartRecruiters, Workable, Recruitee, BambooHR, Breezy, JazzHR, Personio, Teamtailor, iCIMS, SuccessFactors, Eightfold, Phenom, Avature, Cornerstone, and first-party boards for Amazon, Apple, Google, Meta, Tesla, Uber, and ByteDance/TikTok. A few are browser-backed (`WKWebView`).
- Boards can be found by company name (bundled `known-boards.tsv` plus slug probing), added in batches, and searched.
- Polling makes no AI calls. It runs on launch and on Refresh, applies per-board keyword filters, dedupes across boards, and notices postings that have disappeared. The AI runs only when a posting is imported as an application.

**Master Resumes**: named resume presets (for example, "iOS Engineer") carrying the same content fields as an application. A new application copies one wholesale; a master resume can also be previewed as a PDF on its own.

**Employments**: company and role records (dates, location, display order, default role description). Work bullets are grouped and ordered under them on the resume.

**Experience Bank**: one bullet per accomplishment. A bullet has:
- text and any number of named variants (alternate wordings);
- metadata: type (Work, Project, Open Source, …), role category, impact level, claim level, sensitivity, skills;
- an optional owning application, for bullets or variants that should stay private to one application.

A project is one bullet whose text may hold several points, each on its own line starting with `\item`.

## Resume Tailor

Opened from the application editor. Both routes produce the same list of reviewable changes. Each change is applied or reverted individually or with **Apply All**; every applied change stores a snapshot, and revert restores it. A rewrite never modifies a bullet's source text: it is stored as a new variant, or reuses an identical existing one, and that variant is selected for this application.

### External chat (default)

1. **Copy Context** puts on the clipboard the application details, the job description, the resume with every bullet, project, and employer tagged by ID, the unselected bullets, and the output contract for the Resume Edit Plan v1.0.
2. The chat replies with its reasoning and the full tailored resume as text, then one JSON edit plan. **Paste Reply & Import** (⇧⌘V) reads the reply from the clipboard.
3. `ResumeEditPlanImporter` validates the plan with no AI call:
   - it extracts exactly one object carrying `schema_version`;
   - it checks structure and conditional fields, reporting errors as JSON Pointer paths;
   - it resolves every ID, requires every item currently on the resume to be decided (`keep` / `rewrite` / `drop`), checks per-employer ordering, checks that `section_order` matches the sections that will render, and rejects structural LaTeX.
   Any error blocks the import and is listed under the paste box; warnings (a generic variant title, an overlong bullet) do not.
4. The validated plan is adapted into the existing `TailoringPlan`, which feeds the change list.
5. Optionally, generate the PDF, copy its extracted text, and paste the chat's review back. Reading that review does use the in-app AI backend.

The plan covers the fit score, section order, the summary (keep/replace/drop), a three-row Skills table at `0.74\textwidth`, keep/rewrite/drop for each bullet with per-employer `order`, and role descriptions (keep/rewrite/hide, with an optional position among the employer's bullets). The schema and producer rules live in `ResumeEditPlanPrompt.swift`; validation and error codes in `ResumeEditPlanImporter.swift`.

### In-app AI

Runs the Claude Code or Codex CLI:
1. **Fit brief**: fit score, priority, investment tier, candidate story, strong matches, gaps, and questions. With research enabled, it also reads the live posting and public resume guidance.
2. **Clarify**: answers to the questions become recorded facts; capped at five rounds.
3. **Build**: turns the brief into a `TailoringPlan`.
4. **PDF check**: reads the rendered PDF, including its real page count and extracted text, and can propose further edits.

The rules are ported from a standalone `resume-tailor` skill and live in `TailoringPrompts.swift` / `ResumeTailorSkill.swift`.

## Resume content model

`JobApplication` and `MasterResume` share the `ResumeContentModel` protocol. Resume content is stored as flat string fields in `application.yml`:

| Field | Meaning |
|---|---|
| `selected_experience_ids`, `selected_project_ids` | Selected bullets |
| `selected_variant_ids` | Bullet ID → variant ID, per application |
| `experience_order` | One flat ordered list of bullet IDs. Employment IDs in it mark where that employer's role-description line sits; if absent, the line comes first. |
| `section_order` | Summary, Education, Experience, Selected Projects, Skills |
| `summary` | Empty string omits the section |
| `skills_block` | Raw LaTeX override of the profile's skills block |
| `role_descriptions`, `hidden_role_descriptions` | Per-employer role-line wording and visibility |
| `resume_font_size_pt`, `resume_margin_inches` | Page layout |

## Documents

- `ResumeRenderer` fills `{{APPLYKIT_SECTIONS}}`, the name/address placeholders, and the font-size and margin placeholders in the resume template (`Templates/general_resume.tex` with `resume.cls`, or your own template).
- Bullets and summary go through `smartEscapeLatex`, which escapes bare `& % $ # _ ~ ^` but leaves existing commands and hand-escaped characters alone. Metadata (company, role, dates) is fully escaped.
- The PDF is built with the configured command (default `latexmk -pdf -interaction=nonstopmode -synctex=1`) in a login shell. `ResumePDFInspector` reads page count and text back with PDFKit.
- Cover letters: the AI backend returns structured JSON, which is rendered into `cover_letter.tex`.

## Getting Started

### Requirements

- macOS 26
- Xcode 26 to build from source
- Optional: a LaTeX distribution (e.g. [MacTeX](https://www.tug.org/mactex/)) for PDF generation
- Optional: [Claude Code](https://claude.ai/code) CLI or [Codex CLI](https://github.com/openai/codex) for AI features. The external-chat tailoring route and discovery polling work without either.

### Build and test

```bash
open ApplyKit.xcodeproj   # ⌘R to run

xcodebuild -project ApplyKit.xcodeproj -scheme ApplyKit -destination 'platform=macOS' test
```

On first launch ApplyKit asks for a workspace directory and initializes it.

### Settings (⌘,)

- **Workspace:** directory path.
- **AI:** Claude Code and Codex CLI paths (with auto-detect), preferred backend, and per-backend model and effort overrides. If the preferred CLI isn't set, ApplyKit falls back to the other.
- **Resume Tailor:** whether the fit brief reads the live posting and resume guidance.
- **Build:** LaTeX build command and external editor path.
- **Document Templates:** resume and cover-letter `.tex` paths.
- **Profile:** name, contact and online links, education block, and the default skills block.

## Workspace Layout

```
<Workspace>/
├── applykit.yml                  # workspace manifest
├── settings.yml
├── profile.yml                   # identity, contact, education and skills blocks
├── activity-log.yml
├── applications/
│   └── <company>_<title>/
│       ├── application.yml       # fields + resume content (see above)
│       ├── job-description.md
│       ├── notes.md
│       ├── timeline.yml          # status changes, notes, interview steps
│       ├── tailoring-brief.json      # Stage 1 brief, questions, answers, facts
│       ├── tailoring-suggestion.json # current plan, pasted reply, applied/revert state
│       ├── tailoring-review.json     # latest PDF check
│       ├── curated-suggestions.json
│       ├── resume/                   # .tex, resume.cls, PDF, manifest.yml
│       ├── cover-letter/
│       ├── prompts/                  # prompts sent to the AI backend
│       └── ai-responses/             # raw responses, including unparseable ones
├── experience-bank/
│   ├── index.yml
│   ├── <source>/<bullet>.yml     # bullet + variants
│   └── employments/<company>--<role>.yml
├── master-resumes/<name>.yml
├── discovery/
│   ├── boards.yml                # tracked boards and filters
│   └── jobs.yml                  # discovered postings
├── prompts/                      # workspace-level AI runs
└── ai-responses/
```

Every file is plain text and can be read, edited, or version-controlled outside the app. Edits made in the app are written back as you go. The workspace is loaded into memory on launch.

## Architecture

```
ApplyKit/
├── App/               # entry point, sidebar, activity monitor, settings window
├── Domain/            # Codable value types: applications, tailoring plan/brief/review,
│                      # resume edit plan + importer, insights, experience bank, discovery, settings
├── Features/          # SwiftUI views per section (application editor is split by concern)
├── Infrastructure/
│   ├── AI/            # CLI backends, prompt builders, TailoringRunner, edit plan prompt
│   ├── Discovery/     # ATS board resolver, providers, polling service
│   ├── Process/       # subprocess runner, LaTeX build
│   ├── Rendering/     # resume/cover letter renderers, PDF inspector
│   └── Workspace/     # YAML DTOs, file layout, load/sync
├── DesignSystem/      # shared UI components
├── Resources/         # known-boards.tsv
└── Templates/         # default resume/cover letter templates, resume.cls
```

- **State:** a single `@Observable` `AppDataStore` holds the workspace in memory. Views read and write it directly; there is no Combine and no separate view-model layer. `TailoringRunner` owns long AI runs so they survive leaving or closing an editor, and several applications can tailor at once.
- **Persistence:** snake_case YAML DTOs via [Yams](https://github.com/jpsim/Yams), mapped to and from domain types in `WorkspaceFiles`. New fields are optional in the DTOs and get defaults on load, and renamed status values are mapped on load; there is no migration framework.
- **AI:** each run is a one-shot CLI subprocess. Structured replies are parsed from JSON, with one repair call when parsing fails. An empty or unparseable reply is saved to `ai-responses/` and surfaced as an error.
- **Sandbox:** not sandboxed, because it spawns CLI subprocesses and LaTeX. The workspace path and a bookmark are kept in `UserDefaults`.
- **Tests:** XCTest (`ApplyKitTests/`), covering the tailoring plan and edit plan import, rendering, DTO round-trips, job import, discovery, the timeline, interview steps and status sync, and the insights model.

## Contributing

PRs are welcome for bug fixes and focused improvements.

- No new external dependencies without discussion.
- Match existing patterns: `@Observable` state, plain Codable domain types, and one file per entity in the workspace.
- Add or update XCTest coverage for domain and parsing changes, and check UI changes against a real workspace.

## Third-party notices

ApplyKit includes native ports of selected ATS endpoint mappings from [`ats-scrapers`](https://github.com/kalil0321/ats-scrapers). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for attribution.

## License

MIT
