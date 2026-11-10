# Fork maintenance

Maintainer runbook for the `vitorebatista/AeroSpace-edge` fork. All credit for AeroSpace belongs to
[@nikitabobko](https://github.com/nikitabobko) and contributors. MIT license + attribution preserved.

> **For AI agents / future sessions:** this file is the single source of truth for "update my fork
> from upstream." Read it first. It tells you what's already ported (so you don't re-triage), the
> exact commands that work **in this environment**, and the env-specific gotchas. Follow it instead
> of re-discovering everything.

## The fork model

- The fork does **not** blindly track upstream `main`. It sits on a fixed **upstream base commit**
  plus a curated set of **backported bug fixes / small features**, each merged as its own PR.
- We intentionally **skip** large refactors and features that would conflict with the curated
  backports (see "Deliberately not ported" below).
- `origin` = `vitorebatista/AeroSpace-edge` (the fork). `upstream` = `nikitabobko/AeroSpace`.
  **Renamed 2026-08-27** from `vitorebatista/AeroSpace`; GitHub redirects the old URL, but use the new
  name in commands. The fork deliberately uses the `vitorebatista.aerospace-edge` bundle id,
  `AeroSpace-edge.app`, and the `aerospace-edge` CLI so it can be installed alongside upstream.
  Its edge-specific config falls back to the upstream config when no edge config exists.
  If `upstream` is missing: `git remote add upstream https://github.com/nikitabobko/AeroSpace.git`

## Sync state (update this section every sync)

- **Upstream base commit:** `63e0976b` (the fork branched from upstream `main` here).
- **Last upstream review point:** upstream `main` @ `0921fb81`, 115 open upstream PRs (open PRs
  reviewed up to #2385), reviewed 2026-11-09. New work after this point is what a future sync should
  look at. The 2026-11-09 sync found about 150 new `main` commits (`c548c7f8..0921fb81`) and about 60
  new open PRs. It opened fork PRs #77–#94 (see the 2026-11-09 entries in the lists below). Fork PRs
  #83 and #87 conflict in `MacApp.swift`; resolve by keeping both sides (#83's real `pid` plus #87's
  three-value return). (Previous point: `c548c7f8`, reviewed 2026-08-27.) The 2026-08-27 sync found 2 new `main` commits — both
  skipped: `c548c7f8` (`Monitor` → `MonitorInfo` rename, part of the "track upstream main" milestone)
  and `ae2aa7aa` (upstream-only PR-labelling CI) — and 17 new open PRs, of which it ported #2244,
  #2232, #2211, #2228 and #2225 as fork PRs #55–#59.
- **Released:** `v1.17` (cut 2026-11-09): the 2026-11-09 upstream sync, fork PRs #77–#94
  (15 upstream PRs and 3 upstream `main` commits; see CHANGELOG-FORK.md). Lean build (app + CLI).
  Previous: `v1.16.2` (cut 2026-08-31) — fork-original, no backports. Merges fork PR #74:
  `focus-follows-app-activation = 'smart'` no longer leaves a self-activating app's window drawn on
  the current workspace (macOS's `orderFront` pulls the corner-parked window back on screen; the
  suppression path now schedules a refresh that re-parks it). Clears the "KNOWN ISSUE with `smart`"
  recorded under 1.7. Default stays `'always'`.
  Previous: `v1.16.1` (cut 2026-08-31) — fork-original, no backports. Merges fork PRs #71
  (the focused workspace is persisted the moment it changes rather than on the layout snapshot's
  debounce, so an immediate quit no longer loses the last switch; also restores workspaces that
  exist only in a binding, and restores focus even with no usable layout file) and #72 (drop the
  deprecated `macos-14` CI runner).
  Previous: `v1.16` (cut 2026-08-30) — fork-original, no backports. Merges fork PR #66:
  **releases are signed with the stable `aerospace-codesign-certificate` instead of ad-hoc**, so
  macOS keeps the user's Accessibility grant across updates (1.16 itself still re-prompts once —
  ad-hoc → certificate is an identity change); "New" lists workspaces that exist only in a binding
  (`config-version = 2` never materializes them, so the submenu could be empty); a restart returns
  to the workspace you left off on; syntax-highlighted raw TOML editors; "Check for Updates…" moved
  to the Settings footer; a Menu Bar destination that can pin the status item's position; Application
  → Show Crash Reports; and a docs link plus worked examples on every destination.
  Previous: `v1.15` (cut 2026-08-30) — fork-original, no backports. Merges fork PRs #62
  (Settings becomes the single application/configuration surface: direct menu items, Application
  destination, transactional config-version 1→2 migration with a byte-identical backup, and a
  Settings docs section with a page per destination), #65 (native macOS integration: App Intents
  for Shortcuts/Spotlight/Focus filters, layout reacts to display changes, per-app AX messaging
  timeout, `activate(from:)` focus on macOS 14+), #64 (segfault during display reconfiguration,
  Settings-window `SIGTRAP` on NSString-backed config text, window placement remembered across
  restarts) and #63 (`aerospace` → `aerospace-edge` across docs, completion grammar and runtime
  strings — the completions were registered for the wrong command name).
  Previous: `v1.14` (cut 2026-08-29) — fork-original: the Settings window (source-preserving GUI
  editor for the active config; validate-before-write, only edited regions rewritten). No backports.
  Previous: `v1.13` (cut 2026-08-28) — fork-original: menu-bar menu reorganised (in-use workspaces
  only + "New" submenu, "Settings" submenu, Sponsor removed, version copy moved under Check for Updates).
  No backports.
  Previous: `v1.12` (cut 2026-08-27) — fork-original feature: "Check for Updates…" in the menu bar
  with in-place install (see `Sources/AppBundle/updater/`). No backports.
  Previous: `v1.11` (cut 2026-08-27) — fork-original feature: refuses to start while an upstream
  AeroSpace is running (blocking alert, offers to quit the other app, re-checks). No backports.
  Previous: `v1.10` (cut 2026-08-27) — no backports; the fork becomes its own app
  (see "App identity" above), new logo/icon, repo rename, README rewrite, and release zips renamed to
  `AeroSpace-edge-v<ver>.zip` with `legal/` included (1.9's zip shipped an empty `legal/`).
  Previous: `v1.9` (fork PRs #55–#59, cut 2026-08-27) — bug-fix-only cycle:
  iTerm2 Settings window detection (#55), `isUnitTest` hot-path crash (#56), `balance-sizes` total
  weight (#57), `FocusCommand` "is already unbound" race crash (#58), native-tab window replacement
  into the old tree slot (#59). See [`CHANGELOG-FORK.md`](../CHANGELOG-FORK.md) for the per-PR fork
  adaptations.
  Previous: `v1.8` (fork PR #54, cut 2026-07-24) — backports the upstream
  **socket protocol versions handshake** (`8413641c`, previously on the deferred list; explicitly
  requested to fix third-party socket clients — AeroKit, aerospace-swipe, upstream-cask CLI —
  hanging against the fork server). Adaptations: `getIgnoringErrorsOrNil()` → `getOrNil()`,
  EvalCommandTest tweak dropped, guide's Socket-protocol section appended at the end (fork guide
  has no Deprecations section).
  Previous: `v1.7` (fork PR #53, cut 2026-07-24) — first release with a
  fork-original feature: `focus-follows-app-activation = 'always'|'smart'` (suppresses
  cross-workspace focus stealing by self-activating apps; no upstream equivalent).
  `smart`'s known regression (moved windows reappear on the current workspace) was fixed
  2026-08-31 — see CHANGELOG-FORK.md 1.7 "KNOWN ISSUE" for the cause before touching it.
- **Signing gotcha (hit on 1.7 install, fixed by signing with a certificate):** releases used to be
  signed ad-hoc, which invalidates the Accessibility grant on every upgrade; the app then resets its
  own TCC entry and exits at startup (`checkAccessibilityPermissions`), and the user must re-grant:
  System Settings → Privacy & Security → Accessibility (add via + if missing), then relaunch. Releases
  now sign with the stable `aerospace-codesign-certificate` so the grant carries over — see
  "Signing identity: never release ad-hoc" below.
  Previous: `v1.6` (46 backports total; fork PRs #50–#52, 2026-07-18).
  See [`CHANGELOG-FORK.md`](../CHANGELOG-FORK.md).
- **2026-07-23 sync check:** no new upstream-`main` commits (still `d56e1637`); 48 open PRs.
  Only new PR since 2026-07-18: **#2192** "Goodies: add Cyclist" (draft, docs-only one-liner) —
  deferred until it leaves draft.

### Already backported — DO NOT re-port these
Upstream PRs (by upstream number): 2103, 2081, 2012, 2024, 2098, 2052, 1944, 1926, 1953, 1529,
2097, 2080, 1156, 2082, 1665, 1708, 1778, 1932, 2085, 1344, 2083, 1349, 2109, 2116, 2107, 2135,
2162, 2165, 2181, 2167, 2184, 2190, 2188, 2244, 2232, 2211, 2228, 2225,
2338, 2385, 2343, 2348, 2310, 2316, 2335, 2299, 2289, 2326, 2355, 2358, 2369, 2359, 2284
(2026-11-09, fork PRs #77–#93).
Upstream `main` commits cherry-picked / ported: `19b5999d` (swap MRU), `8b236f1b` (die deadlock),
`a0f17f88` (parseConfig exception), `82c4a405`+`cb347265` (Codex window detection, fork PR #33),
`6a2a126d` (workspace next/prev --stdin edge, #34), `dd61a340` (onWorkspaceChanged self-conflicting
focus, #35), `3e381925` (env-var docs, #36), `cfd4eab2` (menu-bar focus steal, #39), `8c3efca2`
(accordion floating-insert, #41), `649301b2` (floating unhide-nudge, #42), `dd6b927a`+`1e6ce27e`
(MacApp AX-destroy-race + wipPids-spin, #43), `4a3aab24`+`d56e1637` (wisprFlow popup detection, #46),
`0f6b2e78` (ignore kCGNullWindowID, #47), `8413641c` (socket protocol versions handshake, #54),
`0921fb81` (macOS 27 menu images, #79), `846f1a22` (concurrent native state/floating rects, #92),
`d080afe4` (`layout --for-next-detected-window`, #94).

### Deliberately NOT ported (skip unless explicitly requested)
- Upstream PR **#2114** "Add sticky window support" — duplicate of our `layout sticky` (PR #2083/#21).
- Upstream PR **#2108** "cycle window size at edge" — conflicts; not requested.
- Large upstream-`main` refactors after our base: the `on-window-detected[*].if` type change
  (TOML table → arbitrary command), the `InterVar` → typed-enum refactor, the
  `ConfigParseError` → `ConfigParseDiagnostic` rework, the Swift bump. These conflict with several
  curated backports. Pulling them in = a **full resync milestone**, not a quick PR — only do it if
  the user explicitly asks to "track upstream main."
- Upstream-`main` refactor chain merged 2026-06-10..06-14 (reviewed 2026-06-15, all part of the
  "track upstream main" milestone, not quick PRs):
  - `4242863b`/`cf6244e7`/`61f0eac9`/`cd64d085` — `ParseConfigResult.errors` → `ConfigParseDiagnostic`
    + readConfig return-type rework (the same family as the `ConfigParseDiagnostic` item above).
  - `317b8d38`/`175b88f6` — ReloadConfigCommand drops `Task.startUnstructured` (absent in fork).
  - `890ec336` — config "warnings mechanism".
  - `a0e43e55`/`6a118fe3` — `test` operator-syntax change + new `test-not` subcommand (breaking
    config-syntax change).
  - `5e37ec0a`/`90347dbb`/`f1f50259` — tree-structure refactor (FloatingWindowsContainer,
    TilingContainerParentCases) — 21-file refactor.
- Upstream **`layout --root` / `--workspace` / empty-workspace** feature set (`11ba9150`, `91064acc`,
  `bb1e5429`, completion fix `4ad2a573`) — features whose semantics sit on top of the `5e37ec0a` tree
  refactor above; can't be cleanly backported without dragging in the refactor. Skipped 2026-06-15
  (not requested). Revisit if/when a full resync happens.
- Upstream-`main` refactor/feature chain merged 2026-06-15..06-26 (reviewed 2026-06-29, all part of
  the "track upstream main" milestone, not quick PRs):
  - **eval/echo command family** (`82ee061c`, `f0c5ab43`, `5c9fc889`, `dac4671a`, `93b65b2d`,
    `0f0a1c80`, `588b1df1`, `6aad5704`, `c69087ec`, `b8e8dbba`, `63df9215`, `88e13b37`, `4b1c4c4c`)
    and `RunCallbackCommand` (`59b181c9`) + its prefactors (`fdb27c59`, `aa1f7ced`, `30566206`).
  - **focusFollowsMouse** (`b95537f2`, `987d1bd5`) and the non-cancellable-session rework
    (`ecfc745c`, `5742362b`, `0ff53e56`).
  - **`ConfigVersion`** strong typing (`5bb3701a`, `5c655bcf`), **`ConvenienceCopyable`** rename
    (`45939229`), **`Parsed`→`ResOrStr`/`ConfigParseDiagnostic`** rename (`c233adb0`), warnings array
    → `ConfigParserContext` (`5e9fdc92`), "Avoid TOML table syntax" (`30e461d7`), and the BREAKING
    "forbid empty `if` in on-window-detected" (`8ceabe9b`) — config-syntax changes that conflict.
  - ~~Socket-protocol versions handshake (`8413641c`)~~ — **ported 2026-07-24 as fork PR #54**
    (explicitly requested), `getNextPrevWorkspace` error-message chain
    (`1aeb8090`/`73a9137c`/`6e472aa3`/`310bd8e1`), accessibility-permission flow (`fb8b1df6`),
    `onWorkspaceChanged` self-conflicting-focus guard (`dd61a340` — already ported as #35).
  - Website/docs-only (`d14b4314`, `3d7fee52`, `61c874bc`, `6e4a2d2c`) and CI (`7d2654d5`).
- Upstream-`main` chain reviewed 2026-07-10 (`fb8b1df6..649301b2`), deferred to a full resync:
  - **focus-follows-mouse** feature (`747e1a97`, `f486beb2`, `9727340a`, `2dc0c786`) — deferred feature.
  - **`ef54f6c5`** (shell: allow comments after backslash) and **`f1cef2eb`** (drop stale
    `ShellParserGenerated`) — both target upstream's hand-written `shellLexer.swift`; the fork still
    uses the ANTLR-generated `ShellLexer`, so these are upstream's move *off* ANTLR, not portable.
  - **`4e240fed`** (isStartup: fix crash) — rewrites `isStartup` against the deleted `_isStartup`
    TaskLocal (`0ff53e56`); the fork's `isStartup` uses `_isStartup ?? dieT(...)`, so the upstream
    fix doesn't map. Revisit during a full resync.
  - **`269dc71b`** (MacApp getOrRegister: loop → single attempt) — targets the same infinite
    re-subscribe loop the fork already bounds via `shouldThrottleFailedRegistration` (fork PR #19);
    adopting it would mean removing the throttle. Its companions `dd6b927a`/`1e6ce27e` WERE ported (#43).
  - **`aa656637`** (make xcode project `git worktree`-friendly + move it) — project-layout
    restructure, not a fix. **`9c922252`** (socket Python example docs) — the fork has no
    socket-protocol guide section. **`e1310b5d`** (bugPrompt graceful/deadly logging), **`5be63812`**
    (update axDumps) — minor upstream-only tooling/data.
- Reviewed 2026-07-14 (`649301b2..d56e1637` + open PRs), deferred (not requested / risky):
  - `a52896b3` (default-config: shorten terminal-launch script) — cosmetic default-config change.
  - Upstream PR **#2174** "Restore windows after native fullscreen" (422 lines) — large feature.
  - Upstream PR **#2176** "add get_tree command" — new command/feature.
  - Upstream PR **#2179** "focus cross-monitor window via private SkyLight API" — risky (private API,
    touches `Package.swift`/`PrivateApi`).
  - Upstream PR **#2180** "Isolate window management from unresponsive apps" — reworks MacApp/
    AxSubscription; conflicts with the fork's AX re-subscribe throttle (`shouldThrottleFailedRegistration`,
    fork PR #19 / #43).
- Reviewed 2026-07-18 (no new `main` commits; new open PRs since 2026-07-14), still deferred:
  - Upstream PR **#2174** "Restore windows after native fullscreen", **#2176**/#2158 "get_tree/get-tree"
    (still open, still large features), **#2179** (private SkyLight API), **#2180** (unresponsive-app
    isolation) — all as noted above.
  - Upstream PR **#2190**'s follow-up `bsp-shape` normalizer (mentioned in the PR, not yet posted) —
    revisit when/if upstream opens it.
- Reviewed 2026-08-27 (`d56e1637..c548c7f8` + 17 new open PRs), deferred:
  - Upstream `main` `c548c7f8` (`Monitor` → `MonitorInfo` rename) — refactor, belongs to the "track
    upstream main" milestone. `ae2aa7aa` (auto-label incoming PRs) — upstream-only CI.
  - Upstream PRs **#2238** and **#2245** (focus-follows-mouse over Control Center / transient
    overlays) — **not portable**: both patch `Sources/AppBundle/mouse/focusFollowsMouse.swift`, and
    the fork never ported the focus-follows-mouse feature (deferred 2026-07-10). Revisit only if
    that feature is ever backported.
  - Upstream PR **#2220** ("on-window-detected 'layout floating' leaves the window at its tile
    origin") — **duplicate**: the fork already fixed this via upstream #2024 (fork commit
    `bad62837`, `isAwaitingOnWindowDetected`). The only delta #2220 adds on top is excluding
    awaiting windows from `layoutAccordion`'s index/padding math; marginal, and #2220 is unmerged.
  - Upstream PR **#2213** ("focus can land on a different window of the same app") — **conflicts
    with fork PR #59**: it deletes `MacApp.lastNativeFocusedWindowId`, which the #2225 native-tab
    backport depends on. Also `mergeable=dirty` upstream, needs `Task.startUnstructured` (absent in
    the fork), and overlaps the fork's own `focus-follows-app-activation` feature. Revisit if
    upstream merges it.
  - Upstream PR **#2206** ("Fix native tab window replacement") — competing implementation of the
    same bug as #2225; **#2225 was chosen** (fork PR #59). Don't port #2206 on top.
  - Feature PRs, deferred as not requested (fork bar is bug fixes + small safe features):
    **#2207** (`list-windows --sort-by`), **#2217** (`list-windows --layout` filter), **#2229**
    (`list-tree` command — same family as the already-deferred #2176/#2158 `get_tree`), **#2240**
    (`default-workspace-monitor` config), **#2241** (`menu-bar-item` config), **#2242**
    (`non-empty-workspaces-root-containers-layout-on-startup` → `tiles|accordion|smart` selector).
  - Still-draft: **#2192** (Goodies: add Cyclist), **#2201** (Restore focus after transient dialogs
    close) — revisit when they leave draft.
- Reviewed 2026-11-09 (`c548c7f8..0921fb81` plus open PRs up to #2385), not ported:
  - **`main` refactors (full-resync milestone):** the native-tabs work-in-progress chain (1/n..22/n,
    `45b2c5d9`..`f5630de7`), the monitor-TreeNode chain (`8ba2e4c1`..`c419f4b2`, which includes
    `58238ba5`), the swift-testing migration (`74fe6426`/`cd5b6f50`), `StrictContinuation`, the
    `OpaqueWindowId`/`windowId_native` renames, the version-via-Mach-O-section change (`78346bcd`),
    and the toolchain/CI/release-validation/xcodegen/swiftformat bumps.
  - **Fixes for bugs the fork doesn't have:** `f337d700` and `a5fee800` (both fix bugs introduced
    by the refactors above), `80092f30` (already covered by #2211, fork #57).
  - **Conflicts with fork design:** `be3e58df`, `b686e0f2` and PR **#2368** (getWindowLevel async
    latch and `.optionAll`; the fork's window-level cache is synchronous and uses
    `.optionOnScreenOnly` on purpose), `9fce49a3` (pure refactor), `2436c969` (cosmetic).
  - **Duplicates or superseded:** **#2272** (superseded by #2316), **#2317** (superseded by #2326),
    **#2281**/**#2324**/**#2342** (same guard as #2228, fork #58), **#2341**/**#2353** (#506
    monitor recursion, already fixed by fork #64).
  - **Blocked or risky:** **#2371** (needs the unported focus-follows-mouse code), **#2344**
    (assumes a single tiling window covers the monitor), **#2339** (about 2k lines of app hiding).
  - **Features, not requested:** #2248, #2271, #2273, #2279, #2285, #2288, #2290, #2291, #2292,
    #2293, #2306, #2307, #2319, #2333, #2334, #2336, #2337, #2340, #2352, #2354, #2356, #2360,
    #2379, #2380, #2381, #2383. Docs/CI/infra: #2286, #2287, #2294, #2304, #2331, #2345, #2364.
    Drafts: #2278, #2280, #2378. Focus-follows-mouse-only: #2238, #2245.
- Upstream CI / build-docs / test-infra commits (`e82b4644`/`78e6dd80`/`ebef281e` GH Actions,
  `2f4d5039`, `c28d3469`, `d07cfee4`, `6ec50638`, `e47d5989`, `abd944d7`, `e063e2fe`) — upstream-only
  tooling or docs for skipped features; nothing to port.

## Updating the fork from upstream — step by step

### 1. Find what's new (cheap; no code changes)
```bash
git fetch upstream --quiet
# New commits on upstream main since our base (already-ported shas are listed above — ignore them):
git log --oneline 63e0976b..upstream/main
# New OPEN upstream PRs (compare numbers against "Already backported" + "Not ported" lists above):
gh pr list --repo nikitabobko/AeroSpace --state open --limit 100 \
  --json number,title,createdAt,isDraft --jq 'sort_by(.createdAt)[] | "\(.number)\t\(.createdAt[0:10])\t\(.title)"'
```
Classify the delta as bug-fix / safe-small-feature / large-feature / docs / obsolete. Default scope
is **bug fixes + safe small features**; confirm scope with the user before porting features.

### 2. Port each item on its own branch off `origin/main`
```bash
git checkout -B port/<slug> origin/main
```
- **From an upstream PR:** get the diff via the GitHub API (NOT `gh pr diff` — it is reformatted in
  this environment and won't `git apply`):
  ```bash
  gh api repos/nikitabobko/AeroSpace/pulls/<N> -H "Accept: application/vnd.github.v3.diff" > /tmp/<N>.diff
  git apply --3way /tmp/<N>.diff      # on conflict: git apply --reject, then re-implement by hand
  ```
- **From an upstream `main` commit:** `git cherry-pick <sha>` (works because `upstream` is fetched).

### 3. Adapt to fork conventions (these differ from upstream)
- **`-strict-memory-safety` is on** → some reads need an explicit `unsafe` marker (e.g.
  `return unsafe _value`) that upstream omits. Add it when the compiler demands.
- **Command results** use `.succ` / `.fail(io.err("..."))` / `BinaryExitCode`, not bare `Bool`.
- **`terminationHandler`** is non-optional in the fork; there is no `Task.startUnstructured`.
- **Window-classification tests are data-driven**: add an `axDumps/*.json5` fixture with the
  expected result inline (e.g. `"Aero.AxUiElementWindowType": "popup"`) rather than a synthetic mock.
- **Generated files** (`cmdHelpGenerated.swift`, `subcommandDescriptionsGenerated.swift`) come from
  `docs-md/commands/*.md`. Edit the page's synopsis fence / `description:` frontmatter, then
  `./script/generate-cmd-help.sh` (build-debug regenerates `subcommandDescriptions`). Never
  hand-edit the generated `.swift`.
- **Docs are part of the change** (see AGENTS.md command checklist): new flag/command/config/format
  var → update the relevant `.md` + `docs-md/guide.md`/`default-config.toml` + the `<event>`/rule in
  `grammar/commands-bnf-grammar.txt`.

### 4. Verify every branch (the bar)
```bash
./script/build-debug.sh -Xswiftc -warnings-as-errors    # must exit 0 (warnings are errors)
./script/swift-test.sh                                   # rely on exit 0 + "✅ Swift tests have passed"
```
The "Test run with 0 tests in 0 suites passed" line is normal (Swift Testing framework); XCTest pass
lines are filtered by the script. IDE/SourceKit diagnostics often lag and show false errors after a
merge — trust the `-warnings-as-errors` build, not the diagnostics.

### 5. Open one PR per fix
```bash
git push -u origin port/<slug>
gh pr create --repo vitorebatista/AeroSpace-edge --base main --head port/<slug> --title "..." --body "..."
```
gh's default repo is the fork (`gh repo set-default vitorebatista/AeroSpace-edge` if ever needed) — always
pass `--repo vitorebatista/AeroSpace-edge` to be safe. PR body: summary + `Ports nikitabobko/AeroSpace#<N>`
(or `Backports upstream commit <sha>`) + test/doc coverage + caveats.

### 6. Merge (local merge train — handles the many shared-file conflicts efficiently)
Merging one-by-one on GitHub triggers cascading rebases. Instead, integrate locally in dependency
order, then push (GitHub auto-marks each PR "Merged" once its branch tip is in `main`):
```bash
git checkout main && git reset --hard origin/main
git merge --no-ff --no-edit origin/port/<slug> -m "Merge pull request #<forkN> from vitorebatista/port/<slug>" -m "<title>"
# ... repeat per branch; merge independent ones first, file-sharing ones adjacently.
```
- **Additive config conflicts** (two PRs both add fields to `Config.swift`/`parseConfig.swift`/
  `ConfigTest.swift`/`default-config.toml`, empty diff3 base) → resolve by **union** (keep both
  sides). Watch for a function whose closing `}` lived in the shared post-conflict region (union can
  drop one brace — add it back; the build will flag it).
- After all merges: one final `./script/build-debug.sh -Xswiftc -warnings-as-errors` + `./script/swift-test.sh`,
  confirm no conflict markers (`git grep -nE '^(<<<<<<<|>>>>>>>)' -- . ':!dev-docs/superpowers'`), then
  `git push origin main`.

## Building a release binary (what actually works in this environment)

`./script/build-release.sh` **fails here** on optional packaging extras (not the app): `script/build-docs.sh`
needs Ruby-under-`mise` on PATH, `script/build-shell-completion.sh` needs `fish` + `bash >= 5` — none are
installed. Two workarounds:

**A. Make the official script work** (if you want man pages + completions): `brew install fish bash`,
and add a `mise` shim so the docs step's rubygems plugin finds it:
```bash
printf "exec '/opt/homebrew/bin/mise' \"\$@\"\n" > .deps/bin/mise && chmod +x .deps/bin/mise
NUKE_PATH=1 PATH="$PWD/.deps/bin:/opt/homebrew/bin:/bin:/usr/bin" \
  ./script/build-release.sh --build-version "1.N" --codesign-identity aerospace-codesign-certificate
```

**B. Lean build (recommended — app + CLI, no man pages/completions).** Put the steps in a script and
run it with `zsh script.sh`, because the interactive shell hook rewrites `rm`/`ls`/etc. (e.g. it turns
`rm -rf` into GNU-flagged `rm` that fails on macOS); running inside a script file bypasses the rewrite.
The script (see git history of `/tmp/lean-release2.sh` pattern) does, with
`NUKE_PATH=1 PATH="$PWD/.deps/bin:/opt/homebrew/bin:/bin:/usr/bin"`:
1. `./script/generate.sh --ignore-shell-parser --ignore-cmd-help --build-version "1.N" --codesign-identity aerospace-codesign-certificate --generate-git-hash`
2. `swift build -c release --arch arm64 --arch x86_64 --product aerospace-edge -Xswiftc -warnings-as-errors`
3. `xcrun xcodebuild clean build -scheme AeroSpace -destination "generic/platform=macOS" -configuration Release -derivedDataPath .xcode-build`
4. `git checkout .` (restores generated files + `project.pbxproj` that xcodegen/version-stamping dirtied)
   > ⚠️ **`git checkout .` discards ALL uncommitted tracked changes, not just the generated ones.**
   > Commit your work *before* running a release build. (Bit us on 1.10: the source half of the
   > rename was wiped and only the docs got committed.)
5. assemble `.release/AeroSpace-edge-v<ver>/` = `AeroSpace-edge.app` (from
   `.xcode-build/Build/Products/Release/`) + `bin/aerospace-edge` (`codesign -s aerospace-codesign-certificate --force`) +
   `legal/`, then `zip -qr`.
- The app is codesigned by xcodebuild with the self-signed `aerospace-codesign-certificate`
  (see below); both binaries come out universal.
- **Verify** baked-in version WITHOUT running the CLI (it can hang in non-interactive shells):
  `plutil -extract CFBundleShortVersionString raw .release/AeroSpace-edge.app/Contents/Info.plist` and
  `strings .release/aerospace-edge | grep <ver>`.

### Signing identity: never release ad-hoc

Release builds **must** use the self-signed `aerospace-codesign-certificate`
(`dev-docs/development.md` step 2 creates it), not `--codesign-identity -`. An ad-hoc signature has no
certificate, so its designated requirement is the literal binary hash
(`# designated => cdhash H"..."`), which changes with every build — macOS TCC then treats each update
as a different app and drops the user's **Accessibility and Screen Recording** grants. Signing with
the certificate gives a stable requirement
(`identifier "vitorebatista.aerospace-edge" and certificate leaf = H"..."`), so the permissions
survive updates. Check with `codesign -d --verbose=4 -r- <app>`.

**This is enforced.** `build-release.sh` refuses an ad-hoc identity outright (pass `--allow-adhoc`
only for a throwaway build that will never be published — CI does), and for a versioned build it
re-reads the designated requirement off the finished `.app` and CLI and fails unless it carries
`release_cert_leaf`, the certificate hash pinned at the top of that script. `codesign -v` alone does
not catch either case: it validates an ad-hoc signature happily.

Back up the certificate + private key (export as `.p12` from Keychain Access). Losing it, or signing
with a different one, costs users one more re-grant — if you deliberately move to a new certificate,
update `release_cert_leaf` in `script/build-release.sh` in the same commit.

**Recovering a user stuck on a stale grant.** Releases `v1.12`–`v1.15` shipped ad-hoc, so anyone who
granted a permission on one of those has a TCC entry pinned to a dead hash. It does not just stop
working: the entry still shows in System Settings, which *blocks* re-granting — the toggle does
nothing and the app cannot be re-added. Clearing it is the only fix:

```bash
tccutil reset Accessibility vitorebatista.aerospace-edge
tccutil reset ScreenCapture vitorebatista.aerospace-edge   # e.g. for `exec-and-forget screencapture`
```

Then re-trigger the permission prompt and approve it. Worth repeating in the release notes of the
first release users upgrade to from `v1.15` or earlier.

## Creating the GitHub release
```bash
gh release create "v1.N" ".release/AeroSpace-edge-v1.N.zip" \
  --repo vitorebatista/AeroSpace-edge --target main --prerelease \
  --title "AeroSpace-edge v1.N" --notes-file <notes.md>
```
- **Version scheme (since 2026-08-27): `1.MINOR[.PATCH]`, independent of upstream.** Minor bump for new
  behavior (upstream backports or a fork-original feature); patch for a fix/docs/packaging release that
  adds no behavior; major only for a breaking config/CLI change. The upstream base commit is tracked in Sync state, not in the version.
  The version shows in the menu bar and `aerospace-edge --version`.
  Releases 1–10 were retagged from `v0.20.3-Beta-fork.N` to `v1.N` on 2026-08-27; only 1.10 was rebuilt
  under the new scheme, so older attached builds still report their original version string.
- Do **not** use `script/publish-release.sh` (it pushes tags to the upstream repo).
- After releasing, **update the "Sync state" section above** and append to `CHANGELOG-FORK.md`.

## Updating the Homebrew tap
The cask lives in [`vitorebatista/homebrew-tap`](https://github.com/vitorebatista/homebrew-tap)
(`brew install --cask vitorebatista/tap/aerospace-edge`). After the GitHub release exists:
```bash
./script/build-brew-cask.sh --cask-name aerospace-edge --build-version 1.N \
  --zip-uri "https://github.com/vitorebatista/AeroSpace-edge/releases/download/v1.N/AeroSpace-edge-v1.N.zip"
cp .release/aerospace-edge.rb <tap-clone>/Casks/aerospace-edge.rb
# commit + push in the tap clone, then:
brew update && brew info --cask vitorebatista/tap/aerospace-edge   # parses the cask
```
- `Casks/aerospace-edge.rb` is generated — never hand-edit it in the tap.
- The generator emits shell-completion/man-page stanzas **only if the zip contains them**, so the lean
  release build (app + CLI only) produces a cask that installs cleanly.
- `brew audit --cask --online` will flag "is a GitHub pre-release" because releases are cut with
  `--prerelease`. Install and upgrade work fine; it's an audit-only complaint.

## CI
`.github/workflows/build.yml` verifies builds across macOS versions once GitHub Actions is enabled on
the fork. `close-third-party-issues.yml` is upstream-only tooling — safe to disable on the fork.

**The runner matrix has diverged from upstream — don't let a sync put `macos-14` back.** GitHub began
deprecating that image on 2026-07-06, fails jobs on it during brownouts through October, and retires
it on 2026-11-02 ([runner-images#13518](https://github.com/actions/runner-images/issues/13518)).
`build-debug` runs on `macos-15` and `macos-26`; `.github/gh-actions-runner-xcode-select.sh` no
longer branches on the OS, because macos-14 was the only runner that could not take Xcode 26.

Dropping the runner did not drop macOS 14 support: the deployment target is still 13.0
(`project.yml`, `Package.swift`), and the `#available(macOS 14, *)` guards in `nativeActivation.swift`
and `MenuBarLabel.swift` are runtime checks for users on 13, not build-time ones. Leave them.

When macOS 27 reaches GA, add `macos-27` and expect `macos-15` to start the same clock — GitHub keeps
only the latest two stable macOS images.
