# ApplyKit

Native macOS app for job application management. Tracks applications through the interview pipeline, maintains a reusable experience bullet bank, and generates tailored LaTeX resumes and cover letters. AI actions (JD analysis, experience recommendations, cover letter drafting) run via Claude Code or Codex CLI as subprocesses. All data persists as YAML and Markdown files in a local workspace directory.

## Sections

**Applications** — Create and manage job applications. Each application stores the job description, status, priority, notes, selected experience bullets, and generated documents. From the application editor you can:
- Run a JD analysis (sends your full experience bank + JD to the AI backend, returns a structured fit assessment)
- Get AI-recommended experience bullets (AI picks the most relevant from your bank based on the JD)
- Refine individual bullets against the JD
- Generate a resume (LaTeX → PDF via your configured build command)
- Draft a cover letter (AI generates structured JSON → injected into your LaTeX template → PDF)

Application status pipeline: `Saved → Interested → Preparing → Applied → Referral Requested → Recruiter Screen → Technical Interview → Final Interview → Offer / Rejected / Ghosted / Withdrawn`

**Employments** — Company and role records. Used to order experience entries on the resume and to provide employment history context to AI prompts.

**Experience Bank** — Library of experience bullets, one per accomplishment. Each bullet can have multiple variants (alternate phrasings), which you select per application. Bullets are tagged with skills, role category, impact level, claim confidence, and sensitivity.

## Getting Started

### Requirements

- macOS 15+
- Xcode 16+ to build from source
- Optional: LaTeX distribution (e.g. [MacTeX](https://www.tug.org/mactex/)) for PDF generation
- Optional: [Claude Code](https://claude.ai/code) CLI or [Codex CLI](https://github.com/openai/codex) for AI features

### Build

```bash
open ApplyKit.xcodeproj
# Cmd+R to run
```

On first launch, a setup sheet asks for a workspace directory. ApplyKit initializes subdirectories there and writes a settings file.

### Settings

Configure in **Settings** (⌘,):
- Workspace directory path
- Claude Code CLI path (for AI features)
- Codex CLI path (alternative AI backend)
- LaTeX build command (default: `latexmk -pdf`)
- Resume template `.tex` path
- Cover letter template `.tex` path
- Profile (name, contact info, education block, skills — injected into generated documents)

## Workspace Layout

```
<Your Workspace>/
├── Applications/       # One YAML file per application
├── Employments/        # Company and role records
├── Experience Bank/    # Bullet points and variants
├── Prompts/            # AI run history (prompt + response files)
├── Documents/          # Generated .tex and .pdf files
└── Settings/           # App config and profile
```

All files are plain text; you can read, edit, or version-control them independently of the app.

## Customization

**Templates** — Provide your own `.tex` files for resume and cover letter. At generation time ApplyKit injects profile fields, education/skills blocks, and selected experience bullets. Set template paths in Settings.

**Experience bullet metadata** — Each bullet has fields for role category (General SE, Backend, AI Tooling, Mobile/iOS, etc.), impact level, claim confidence (`Safe` / `Contextual` / `Don't emphasize`), and sensitivity (`Public` / `Internal-safe` / `Sensitive`). Populate these to improve AI recommendation quality and to filter bullets when selecting for an application.

**AI backend** — Set Claude Code or Codex CLI path in Settings. The app uses whichever is configured. All prompts are built internally and are not user-editable; raw prompt and response files are saved to `<Workspace>/Prompts/` per run for inspection.

## Architecture

```
ApplyKit/
├── App/               # Entry point, root navigation, activity monitor
├── Domain/            # Data models
├── Features/          # SwiftUI views per section
├── Infrastructure/    # Workspace I/O, subprocess runner, LaTeX renderer, prompt builder
└── DesignSystem/      # Shared UI components
```

**State:** `@Observable` (Swift 5.9) throughout — no Combine, no separate view model classes.  
**Persistence:** YAML + Markdown via [Yams](https://github.com/jpsim/Yams) (Swift Package Manager).  
**Sandbox:** Security-scoped bookmarks retain workspace access across launches.

## Contributing

PRs are welcome for bug fixes and focused improvements.

- No new external dependencies without discussion
- Match existing patterns: `@Observable` state, one YAML file per entity in the workspace
- Test against a real workspace directory — there are no automated tests

## License

MIT
