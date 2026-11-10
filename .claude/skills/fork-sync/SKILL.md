---
name: fork-sync
description: >-
  Sync the vitorebatista/AeroSpace-edge fork with upstream nikitabobko/AeroSpace. Finds new upstream
  commits and open PRs since the recorded sync point, triages them (bug fixes + safe small
  features), backports the delta as individual build+test-verified PRs, can merge them via a
  conflict-aware merge train, cut a `1.N` release, and update the changelog/sync-state docs.
  Use this WHENEVER the user asks to update/sync the fork, check the upstream/main repo for new
  changes/PRs/fixes to bring in, backport upstream bug fixes, refresh the fork from upstream, or
  "update my fork with the main repo" — even if they don't say the word "skill". It is built to be
  low-token: it reads the recorded sync state to avoid re-triaging the whole upstream PR list.
---

# Fork sync

Keep the `vitorebatista/AeroSpace-edge` fork current with upstream `nikitabobko/AeroSpace` by backporting
only the *new* worthwhile changes since the last sync — cheaply, without re-triaging everything.

All credit for AeroSpace belongs to [@nikitabobko](https://github.com/nikitabobko). Preserve the MIT
license and attribution in everything you produce.

## Read this first

**`dev-docs/fork-maintenance.md` (repo root) is the single source of truth.** Read it before doing
anything — it holds the exact, environment-specific commands plus three things that make this fast:
the **Sync state** (upstream base, last review point, **already-ported list**, **deliberately-skipped
list**), the fork **code conventions**, and the **lean release build** steps. This skill is the
orchestration layer on top of that runbook; don't duplicate its commands here, follow them there.

Also relevant: `AGENTS.md` (build/test bar, generated files, doc checklist — `CLAUDE.md` is a symlink
to it) and `CHANGELOG-FORK.md`.

## Path map: the fork's layout is not upstream's

**An upstream diff will not apply cleanly to a path the fork has moved or replaced.** Check this table
before `git apply`/`git cherry-pick`, and re-apply the change by hand on the fork's side of the map
when it hits one of these. Everything not listed sits at the same path in both repos.

| Upstream | Fork | What it means for a port |
|---|---|---|
| `docs/*.adoc` (asciidoc site + man pages) | `docs-md/**/*.md` (Material for MkDocs, `mkdocs.yml`) | **The big one.** Any doc hunk in an upstream diff will fail. Rewrite it as Markdown: a command's page is `docs-md/commands/<command>.md` (` ```synopsis ` fenced block + `description:` frontmatter), the guide is `docs-md/guide.md`. |
| `docs/aerospace-<command>.adoc` synopsis | ` ```synopsis ` block in `docs-md/commands/<command>.md` | Regenerate with `./script/generate-cmd-help.sh` (feeds `Sources/Common/cmdHelpGenerated.swift`). Never hand-edit the generated `.swift`. |
| `docs/index.html`, `docs/util/` | gone (mkdocs builds the site; see `.github/workflows/docs.yml`) | Drop those hunks. |
| `docs/config-examples/` | same path, symlinked in as `docs-md/config-examples` | Unchanged — apply normally. The symlink exists because mkdocs needs the TOML inside `docs_dir`. |
| `xcode/` | same path since the 2026-11 resync (`xcode/project.yml` + `xcode/AeroSpace.xcodeproj`, xcodegen) | Applies normally, but the fork's `PRODUCT_NAME`/`PRODUCT_BUNDLE_IDENTIFIER` and the `AppIntents.swift` entries must survive; regenerate with `./script/generate.sh`. |
| — | `dev-docs/superpowers/` (plans + specs), `CHANGELOG-FORK.md`, `dev-docs/fork-maintenance.md`, `AGENTS.md`/`CLAUDE.md`, `.claude/` | Fork-only. Upstream never touches these, so they never conflict. Moved out of `docs/` on 2026-08-30 — old references say `docs/superpowers`. |

Naming diverges too: the app is `AeroSpace-edge.app`, the CLI `aerospace-edge`, the bundle id
`vitorebatista.aerospace-edge`. Upstream diffs carrying the bare `aerospace` name in **user-visible
strings, docs, or the completion grammar** need renaming as part of the port (see fork PR #63, which
fixed exactly this being missed).

**Packaging:** `script/build-brew-cask.sh` has fork-specific changes (conditional completion/manpage
stanzas, no `conflicts_with`, fork caveats) and feeds `vitorebatista/homebrew-tap`. Take upstream
changes to it by hand, never wholesale.

## The efficiency principle

The upstream repo has 50+ open PRs and a moving `main`. Re-triaging all of it every time is slow and
token-heavy. Instead: the runbook records exactly what's already ported and what was deliberately
skipped, plus the last upstream commit/PR review point. **Only look at the delta past that point**,
and skip anything already on the ported/skipped lists. After a successful sync, you MUST update the
Sync state so the next run stays cheap (see Phase 6).

## Workflow

Run phases in order. Phases 1–3 are the core ("check + open PRs"); 4–5 happen only when the user asks
to merge / release; 6 always runs after you change anything.

### Phase 1 — Find the delta (read-only, cheap)
Follow the runbook's "Find what's new" commands: `git fetch upstream`, list upstream `main` commits
since the recorded base, and list open upstream PRs created since the last review point. Drop anything
already on the **already-ported** or **deliberately-skipped** lists. You're left with a small candidate
set — not the whole backlog.

### Phase 2 — Triage + confirm scope
Classify each candidate: bug-fix / safe-small-feature / large-feature / docs / obsolete / duplicate.
Default scope is **bug fixes + safe small features** (the fork's established bar). Before porting
anything that's a feature or a large/risky change, briefly present the candidates and confirm scope
with the user. Flag duplicates of existing fork features and large upstream refactors (which usually
belong to a separate "full resync" milestone, not this skill) rather than porting them silently.

When the candidate set is large, fan out **parallel read-only agents** to triage in batches (each
agent reads PR diffs/metadata via `gh` and reports a structured verdict) — this is cheap and fast.

### Phase 3 — Bring the changes in
**Upstream `main` commits:** since the 2026-11 full resync the fork tracks upstream `main` by merging it
(`git merge upstream/main` on a `resync/<date>` branch, resolve conflicts with "upstream wins on structure,
every fork behaviour survives on top", build + test, one PR). Prefer that over cherry-picking individual
upstream-main commits. **Open (unmerged) upstream PRs** are still backported one by one, as below.

Per the runbook, for each unmerged upstream PR: branch off `origin/main` (`port/<slug>`), apply the change
(`gh api .../pulls/<N> -H "Accept: application/vnd.github.v3.diff"` + `git apply --3way`, or
`git cherry-pick <sha>` for upstream-main commits), adapt to fork conventions
(`-strict-memory-safety`, `.succ`/`.fail(io.err())`/`BinaryExitCode`, data-driven `axDumps` tests,
generated files from `docs-md/`), **translate every doc hunk through the path map above**, satisfy the
**doc checklist** (`docs-md/commands/<command>.md` synopsis+body, `docs-md/guide.md`/
`docs/config-examples/default-config.toml`, `grammar/commands-bnf-grammar.txt`), then verify with
`./script/build-debug.sh -Xswiftc -warnings-as-errors` **and** `./script/swift-test.sh` before opening one PR per
fix with `gh pr create --repo vitorebatista/AeroSpace-edge --base main`.

Porting does heavy Swift builds, so run port agents **serially in the shared working copy** (warm
`.build` cache, no branch clobbering) rather than many parallel cold builds. Each PR body must cite
`Ports nikitabobko/AeroSpace#<N>` or `Backports upstream commit <sha>` plus test/doc coverage. Trust
the `-warnings-as-errors` build over lagging IDE/SourceKit diagnostics.

### Phase 4 — Merge (only if the user asks)
Use the local **merge train** in dependency order, then push (GitHub auto-marks PRs merged once their
branch tip lands in `main`). Resolve additive config conflicts by **union** (keep both sides), watching
for a dropped closing brace. Finish with one integrated `build-debug` + `swift-test` and a
no-conflict-markers check before `git push origin main`. See the runbook for the exact recipe.

### Phase 5 — Release (only if the user asks)
Use the runbook's **lean release build** (the official `script/build-release.sh` fails in this environment on
docs/shell-completion tooling). Bump the version (`1.MINOR[.PATCH]` — minor when the release carries backports), build the
universal app + CLI, then
`gh release create v<ver> --repo vitorebatista/AeroSpace-edge --target main --prerelease <zip>`.
Then **publish the cask** — regenerate with `./script/build-brew-cask.sh` and push it to
`vitorebatista/homebrew-tap` (runbook → "Updating the Homebrew tap"). A release that isn't in the tap
leaves `brew upgrade` users behind.

### Phase 6 — Update the markdown (always, after any change)
This is part of the job, not an afterthought — it's what keeps future syncs cheap and the repo honest:
- **`CHANGELOG-FORK.md`** — add a section for the new backports (link upstream PR/commit + fork PR #).
- **`dev-docs/fork-maintenance.md` → Sync state** — update the **last review point** (latest upstream
  commit/date + open-PR count reviewed), extend the **already-ported list**, add anything new to the
  **deliberately-skipped list**, and bump the released version when you cut one.
- Any command/flag/config docs touched by the ports, per the AGENTS.md doc checklist.
Commit these doc updates (a small PR, or directly to `main` if the user wants them available
immediately for the next session).

## Output / what to report
End with a concise summary: candidates found, what was ported (with fork PR numbers + URLs), what was
skipped and why, build/test status, and — if done — merge results and the release URL. If you paused
for scope confirmation, say exactly what you're waiting on.

## Guardrails
- Never commit fixes directly to `main`; each backport is its own branch + PR off `origin/main`.
- Don't pull in large upstream refactors or duplicate existing fork features without explicit opt-in.
- Don't fake tests; if behavior is runtime/Accessibility-only, say so in the PR rather than inventing a test.
- Keep upstream attribution + MIT license intact.
