# Error handling verification — 2026-09-08

## Current unverified changes — 2026-09-09

Added session provenance for runtime missing-package alerts. A successfully read completion
snapshot with no remaining execution errors clears a runtime alert; restart, disconnect
and session reset clear its obsolete alert. Imported requirements without runtime provenance
are preserved. Added completion/remaining-error and restart regression cases. Native HTML
text now supplies its text as an accessibility value alongside its descriptive label.

These changes are **not verified**. ToolUseProxy rejected the test command before execution
because its protection decision exceeded the deadline. Retrying after separate code edits
and reads did not resolve it. No protection settings were modified. Prior 245-test results
and the structured candidate archive predate these changes. Native Open-panel behavior is
still unresolved and has not been patched speculatively.

## Acceptance contract

A Python exception must not terminate the macOS app. The error must remain readable (including through accessibility), unsuccessful execution must not show a success checkmark, and editing, saving and another authorized execution must remain possible. Transport failure must preserve the editor buffer, end transient waiting states or offer bounded recovery, and never silently replay user code.

## Test layers and cases

| Layer | Cases | Required observations |
| --- | --- | --- |
| Real bundled Python | SyntaxError, NameError, ZeroDivisionError, missing module, Japanese ValueError | Error output; idle session; unchanged source and dirty flag; no success indicator; successful rerun in the same session |
| Store with injected failures | Unacknowledged restart; rejected execute request; disconnection during execution | Bounded failure; no permanently queued cell; results marked stale; buffer retained |
| Existing recovery integration | Infinite loop interrupt; SIGKILL of the test sidecar | Bounded interruption; child-process cleanup; restart and resynchronization of unsaved content |
| Protocol | Timeout, cancellation, disconnect, pending request cleanup | Awaiters resume, errors propagate, no leaked pending requests |
| Output decoding | Unsupported/malformed/oversized output | Recoverable renderer failure instead of app termination |
| Native app | Error details expand/collapse, error-to-success transition, accessibility tree read | App stays alive, actual error and traceback readable, controls remain operable |

Automated additions: `ExecutionFailureRecoveryTests.pythonFailureRecoveryMatrix` uses five failures, each followed by a successful execution. `NotebookSessionTests` adds restart timeout, disconnected-run status and execute rejection regressions. Use isolated temporary support directories and synthetic sources, never user notebooks or live protection configuration.

## Confirmed defects fixed in this audit

1. Session-resolution timeout ignored `.restarting`, allowing indefinite restart state. The timer now covers startup and restart. Regression failed before the change.
2. Disconnect reset runtime status to idle while retaining a matching last-executed source with stale=false. This could falsely show success for interrupted execution. Disconnect now marks retained outputs stale and cancels completion refresh. Regression failed before the change.
3. A rejected execute request left cells queued. Failure now ends those transient states and marks their retained outputs stale. Regression failed before the change.

## Evidence and limits

Baseline full `swift test`: 186 unit tests (15 issues), 39 integration tests (1 performance issue), 8 contract tests passing. Failures include assertions demanding the superseded NavigationSplitView/inspector/toolbar layout, environment candidate assumptions and the 1-second notebook-open p95 threshold. They are not silently waived or counted as a green release suite.

The September 8 20:27 crash report records accessibility-label recursion and stack exhaustion. The previous fix removed compound error Labels and nested Button(configuration) styling and made error/traceback accessibility containers explicit. The original crash has not been deterministically reproduced; successful native runs do not prove its complete elimination. Native accessibility stress and longer repeated runs remain release gates.

Run All dependency policy has now been verified with a real three-cell notebook: a dependent displayed above its failing ancestor is prevented from succeeding, while an independent branch still produces 42. Fixing the ancestor recovers its dependent. The obsolete Swift display-order fail-fast implementation was removed to follow specification sections 2/4 and the existing marimo delegation contract. A synthetic error-status test now asserts that Swift does not interrupt unrelated work.

## Repeatable commands

Set DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer.

- `swift test --filter 'NotebookSessionTests|pythonFailureRecoveryMatrix|interruptAndProcessCleanup|sidecarCrashReopensDirtyDocument|JSONRPCConnectionTests|OutputTests'`
- `swift test` for the broader release baseline (known failures must be triaged).
- Build both `sh Tools/build-debug-app.sh` and `xcodebuild -project Lunamo.xcodeproj -scheme Lunamo -configuration Debug build`.
- In the freshly built app, execute `np`, expand/collapse Details, replace with `40 + 2`, execute again, and read the accessibility tree at each step. Repeat with `raise ValueError('日本語の検証エラー')`. Check new crash reports, not merely the build exit code.

## Remaining release gates

Deterministic reproduction of the original native crash; repeated error/accessibility transitions; direct kernel-process termination (distinct from sidecar termination); interrupted-run saving and reopen verification; clean-machine testing. Signing is tracked separately from runtime reliability.

## Final audit run

- Focused automated run: 35 unit tests in 3 suites and 22 integration tests in 2 suites passed (57 total). Includes all three before/after regressions, the five real Python error/recovery cycles, real interrupt/cleanup and sidecar crash recovery.
- Baseline failures above remain separate and unresolved; the complete suite is not green.
- Packaged debug build succeeded. Xcode build result is recorded in `/tmp/lunamo-error-audit-xcode.log`.
- Fresh native verification in this audit was blocked by Computer Use's repeated ScreenCaptureKit -3811 capture failure. Earlier-turn native observations are not represented as verification of this audit's new recovery changes.
- Local logs: `/tmp/lunamo-error-audit-tests.log` (baseline), `/tmp/lunamo-error-audit-red.log` and `/tmp/lunamo-error-request-red.log` (regressions before fixes), `/tmp/lunamo-error-audit-final-tests.log` (focused passing run).


## Publication-quality continuation

- Removed Swift display-order failure propagation; real Run All dependency-branch test added.
- Isolated the bundled-environment test from the user's app-managed Python installation.
- Updated superseded source-structure checks to the accepted workspace/toolbar implementation. Native width allocation and resize hit testing remain exercised by dedicated behavioral tests; execution-error outcome assertions now use the tested runtime predicate.
- Full suite is being rerun after these changes; no release-success claim until its result is reviewed.
- Computer Use still reports ScreenCaptureKit -3811 during this continuation. Native verification remains open.

Latest complete run (`/tmp/lunamo-release-full.log`): 189 unit tests passed, 40 of 41 integration tests passed, 8 contract tests passed. The sole failure is warm-open p95=1583.61 ms against the existing 1000 ms requirement; do not relax the threshold. Xcode build passed. Developer ID Application is not currently installed (only a development signing identity is available). Next work: profile notebook-open latency and remove the bottleneck, then complete native/offline/archive verification when available.

## Notebook-open profiling

Local phase measurements showed approximately 0.27–0.29 seconds through document read, parsing, text-cell projection and synchronization, followed by approximately 0.86–0.97 seconds in environment discovery. Discovery synchronously enumerated the installed managed Python environment and package cache to calculate storage usage for Settings on every open. Removed that storage enumeration from document discovery; Settings' explicit refresh still computes it. Temporary timing prints were removed. The 1000 ms performance requirement is unchanged; a complete suite rerun is required to accept the improvement.

Performance fix accepted by the unchanged complete test suite: `/tmp/lunamo-release-performance-fixed.log` reports 189 unit + 41 integration + 8 contract tests passing (238 total). Warm-open p95 is 419.79 ms across 20 samples, below the existing 1000 ms limit. This supersedes the earlier failing baseline but does not close native UI, clean-machine or signed-archive gates.

## Kernel-exit and native verification continuation

- Added `abruptKernelExitRecovery`: actual Python calls `os._exit(17)` after writing a marker in an isolated temporary workspace. Edited source survives explicit kernel restart; restart does not execute edited code; explicit execution succeeds; Save As and reopen preserve the recovered source and clean dirty state. Passed (`/tmp/lunamo-kernel-exit.log`, 4.78 seconds).
- Computer Use recovered. Relaunched the current `.build/Lunamo.app`, executed a Japanese ValueError, observed the actual exception text and traceback through accessibility, toggled Details ten times while reading the tree, then changed source to `40 + 2` and observed the success checkmark and output node. App remained alive; quit displayed the unsaved-changes guard, and the disposable test buffer was discarded.
- Screenshot output remains too small for pixel-level visual acceptance. These observations establish native interaction/accessibility behavior, not visual polish or deterministic reproduction of the original stack-recursion crash.
- Earlier direct-kernel-termination and save/reopen gaps are now covered by the new integration test. Signed archive, clean host, offline acceptance, larger output-scroll profiling, and extended native stress remain open.

## Artifact/offline audit

- Debug packaged sidecar structure/version/isolation and Python contract checks passed (`/tmp/lunamo-artifact-sidecar.log`).
- Packaged sidecar initialize/parse/print/runtime/shutdown passed with external networking denied (`/tmp/lunamo-offline-sidecar.log`).
- Packaged app acceptance probe passed in an isolated home with external networking denied: open/edit/save/Python selection/trust/execute output 43/cleanup (`/tmp/lunamo-offline-app.log`). This is an in-app acceptance probe, not manual UI automation or a clean-machine result.
- Built Release configuration with ad-hoc hardened signatures. Structural signing passed, but msgspec dlopen failed library validation due to Team ID mismatch (`/tmp/lunamo-release-artifact.log`). No weakening entitlement was added. A development-certificate build is being checked separately; Developer ID/notarization remains required for distribution.
- Fixed requirement enumeration to include suffixed IDs (019A/019B). Added a regression test (`Tests/Contract/test_requirement_coverage.py`, passed). Coverage now enumerates 465 mandatory requirements; ENV-019A/B explicitly remain manual acceptance, not inferred passing results.
- Added and passed persistence assertions showing Project Environment selection survives registry reload and leaves another workspace on Shared.

Development-certificate Release artifact verification completed successfully: `/tmp/lunamo-development-artifact.log` reports strict hardened signing validation of 20 nested Mach-O files, bundled sidecar contract/version checks, network-denied runtime acceptance, and packaged app open/edit/save/trust/execute/cleanup. Artifact: `.build/development-release-audit-20260908/Lunamo.app`. No library-validation bypass entitlement was used. Distribution identity, notarization, clean-host acceptance and release performance profiling remain open.

## Release performance run

On the development-signed Release artifact, cold-window p95=365.27 ms (20 launches) and app+sidecar RSS=181.72 MiB passed. Scroll maximum main-thread delay=105.96 ms failed the unchanged 100 ms limit. Repeated without concurrent archive creation: cold-window p95=361.71 ms, RSS=201.88 MiB, scroll=108.44 ms. The scroll failure is reproducible and remains open, not waived. Logs: `/tmp/lunamo-release-performance.log`, `/tmp/lunamo-release-performance-isolated.log`.

Created a local development audit ZIP with SHA-256 49cef4ef6c4816c683b4cd0812bc3f84cb89c26f57f3bc597174491dbbb090d3 and a pending checklist (23 manual-only entries) in `.build/development-release-audit-20260908/`. This is not a distributable notarized release.

Optimized Release compilation was retried with the current Xcode toolchain (`/tmp/lunamo-optimized-release-build.log`) and still fails in SwiftSoup's SIL CopyPropagation pass. The existing global -Onone workaround therefore cannot simply be removed. Investigate narrowing that compiler workaround or reducing main-thread layout work before accepting the scroll gate. The failed experiment did not replace the verified signed audit bundle.

## Narrowed compiler workaround

Optimized compilation succeeded with `-Xswiftc -Xllvm -Xswiftc -sil-disable-pass=CopyPropagation` (`/tmp/lunamo-selective-optimization.log`, 99.81 seconds). `Tools/build-release-app.sh` now disables only that crashing SIL pass instead of applying -Onone to all modules. Building a separate optimized development-signed artifact; performance and runtime acceptance must be rerun before accepting it. Added the Python requirement-coverage test to SwiftPM's explicit exclusions to avoid an unhandled-file warning.

The optimized development-signed artifact built successfully in `.build/optimized-release-audit-20260908/`. Its performance run still failed the scroll limit (167.28 ms; `/tmp/lunamo-optimized-performance.log`), so narrowing the compiler workaround is not a demonstrated scroll fix. Optimized test suite is running separately (`/tmp/lunamo-optimized-tests.log`). An initial sample omitted the window-marker launch flag and did not produce a scroll completion marker; it must not be treated as a completed scroll profile.

## Restart race found by optimized tests

The initial optimized full suite passed 189 unit and 8 contract tests but failed two assertions in abruptKernelExitRecovery: stale executed-source metadata could return during restart and the next run did not reliably recover. Added retirement of replaced session IDs in kernel notifications/session lookup, cancellation of completion refresh on restart, and post-await document/URI/session checks before applying completion snapshots. Added delayed old-session notification and delayed completion-snapshot regression coverage. Debug focused run passed (see `/tmp/lunamo-restart-race-verified.log`); optimized focused verification is running in `/tmp/lunamo-restart-race-release.log`.

Scroll probe now initializes distinct image data for each cell instead of reusing one cached image for all 100 cells. It records maximum synchronous layout duration and the slowest step separately, without relaxing the 100 ms limit. The revised diagnostic artifact is `.build/scroll-profile-audit-20260908/Lunamo.app`; it predates the final restart-race changes and is for scroll diagnosis only.

## Lifecycle-test timing correction and distinct-image run

The first optimized restart assertion ran while sessionState was still starting: the Python marker precedes delivery of lifecycle notifications. The test now waits up to five seconds for restart availability before asserting; it also requires prerequisites before dependent operations and shuts down the backend on thrown failure. Optimized focused rerun passed in 4.75 seconds (`/tmp/lunamo-exit-notification-order.log`). This does not undo the independently tested stale-notification/snapshot protections.

With distinct initialized images, Release performance measured cold launch p95=459.91 ms, RSS=200.58 MiB and maximum scroll delay=85.51 ms (`/tmp/lunamo-distinct-image-performance.log`). One passing result does not settle prior variability; a repeat is in progress. The performance tool now preserves the probe's detailed layout timing in its output.

Distinct-image repeat also passed (`/tmp/lunamo-distinct-image-repeat.log`): cold launch p95=348.49 ms, RSS=200.86 MiB, max scroll delay=83.09 ms, maximum synchronous layout=39.03 ms (step 215). Two consecutive runs satisfy the fixed thresholds on this artifact. Final rebuilt artifact must include the latest restart-race changes and repeat automated/runtime acceptance before release audit completion.

## Latest candidate verification

- Full optimized suite passes: 190 unit, 42 integration, 8 contract (240 total), `/tmp/lunamo-final-release-tests.log`. Warm-open p95 245.95 ms.
- Exact development-signed candidate `.build/final-local-candidate-20260908/Lunamo.app` passed hardened signature checks for 20 nested Mach-O files, bundled contracts and network-denied packaged app flow (`/tmp/lunamo-final-artifact-verification.log`).
- This candidate passed performance gates: cold-window p95 339.60 ms over 20 launches, app/sidecar RSS 199.81 MiB, 100-cell/50-MiB-image scroll max delay 78.47 ms (`/tmp/lunamo-final-candidate-performance.log`).
- Strengthened Run All recovery test to require actual downstream output 41 after fixing its ancestor, and independent output exactly 42. Both failure-matrix and dependency tests now clean up their backend on thrown failure. All three real failure/recovery tests pass again in optimized Release (`/tmp/lunamo-final-strengthened-recovery.log`). These final changes affect tests only, not candidate runtime code.
- Added requirement-enumeration regression to the local gate script used by CI; its isolated run passes. This is local verification, not a claim that remote CI ran.
- Latest native candidate interaction attempt failed before inspection with Computer Use ScreenCaptureKit -3811. Prior debug-app observations do not close the exact-candidate native acceptance gate. Developer ID/notarization and clean supported-host acceptance remain pending.

## Recovery retry audit

Found another recovery dead end: restart clears the kernel session ID before contacting the backend, but restart availability previously required that ID even after failure. Both a rejected restart request and an unacknowledged restart therefore disabled retry. Added a two-case regression; it failed with ten assertions before the fix (`/tmp/lunamo-restart-retry-red.log`).

Explicit restart is now available in failed state when backend and Python environment are ready. If its ID is missing, the restart request permits creating a missing session. It still does not execute notebook code. Focused Release tests passed: 26 session tests and 3 real recovery tests (`/tmp/lunamo-restart-retry-green.log`). Added real sidecar coverage of missing-session creation and explicit subsequent execution; full Release rerun pending.

The earlier final-local-candidate artifact predates this runtime change and is no longer the current source candidate.

The initial new integration test incorrectly waited for NotebookStore UI state after invoking the adapter directly (without entering Store's restart transition). It now inspects the adapter's session registry and empty output snapshot, then requires that explicit Store execution creates the marker and output 42. This passed in 2.91 seconds (`/tmp/lunamo-missing-session-check.log`). State-transition/retry behavior remains separately covered by the two-case Store regression; neither assertion replaces the other. Final full rerun: `/tmp/lunamo-retry-full-release-final.log`.

Final optimized rerun passes all 242 tests (191 unit + 43 integration + 8 contract). Next artifact build: `/tmp/lunamo-retry-candidate-build.log`, `.build/retry-candidate-20260908/Lunamo.app`; artifact/native checks remain pending.

## Retry candidate artifact and scroll audit

Latest retry candidate built and passed strict development signing (20 nested Mach-O) and offline packaged acceptance (`/tmp/lunamo-retry-artifact.log`). Performance on that binary: launch p95 345.15 ms, RSS 203.75 MiB, scroll max 106.41 ms, layout max 57.31 ms (`/tmp/lunamo-retry-performance.log`). Scroll fails the unchanged 100 ms requirement; prior candidate passes do not waive it.

User unlocked Mac. Computer Use inventory recovered after resetting the session, but selecting the exact app still failed with ScreenCaptureKit -3811. Native acceptance is still pending; do not ask for unlocking again without new locked-state evidence.

Sampling `/tmp/lunamo-retry-active-scroll-sample.txt` captured active `runScrollProbe` layout work. Of 2370 samples under forced layout, substantial hover action stacks pass through CellView.updateHoverCursor/restoreHoverCursor to NSCursor and AccessibilityFoundation cursor image generation. This is a concrete optimization lead, not proof that cursor updates alone explain the maximum delay. The sampled run was terminated after the eight-second sample without a scroll completion marker, so it is not a completed performance acceptance run. The earlier `/tmp/lunamo-retry-scroll-sample.txt` did not establish active scroll and is not used as scroll evidence.

## Cursor update coalescing

Added CellCursorCoordinator to collect per-view cursor requests and apply only the final style after the current synchronous layout pass. A view owns a UUID token, so another cell's delayed hover-exit cannot pop its cursor. Dragging takes precedence over hover; an unchanged effective style does not touch NSCursor. CellView delegates grab/pointer/drag state and removes its request on disappearance.

Three deterministic transition tests pass (`/tmp/lunamo-cursor-tests.log`): 100 cell crossings coalesce without repeating the effective cursor, late exit preserves the other control's pointer, drag cleanup returns to the remaining hover then restores the cursor. The source-boundary checks now inspect the coordinator for AppKit push/pop rather than requiring those calls in CellCursorBehavior. Full Release run: `/tmp/lunamo-cursor-full-tests.log`. Native semantics and measured performance are not yet accepted; retry-candidate predates this UI change.

Cursor candidate `.build/cursor-candidate-20260908/Lunamo.app` built successfully. Full optimized suite passes 245 tests (194 unit + 43 integration + 8 contract). Two consecutive performance runs pass unchanged thresholds: launch p95 342.98/342.82 ms; RSS 201.38/200.64 MiB; maximum scroll delay 86.56/69.51 ms; max synchronous layout 48.55/43.73 ms. Logs: `/tmp/lunamo-cursor-performance.log`, `/tmp/lunamo-cursor-performance-repeat.log`. These establish two local passing runs, not a universal absence of stutter. Native cursor acceptance and packaged verification of this new candidate remain pending.

The source-policy gate was also run and fails because CellView, NotebookAssistantView, NotebookRootView, NotebookSession and NotebookStore exceed 500 lines (`/tmp/lunamo-cursor-source-policy.log`). Do not claim all repository gates pass based on the Swift test suite.

## Source-policy completion

Split the five oversized source files by responsibility: CellExecutionControls, NotebookRootToolbar, NotebookAssistantConversation, NotebookOpening and NotebookRuntimeOutput. Moved declarations intact, changing private members to module-internal only where cross-file extensions require it. Source-boundary tests now inspect both files for the moved declarations; behavioral assertions were retained. Initial structural failures from old file-only reads were corrected; final Release suite passes all 245 tests (`/tmp/lunamo-split-final-tests.log`).

Source policy, pinned protocol verification, all 465 mandatory requirement mappings and recursive strict swift-format lint pass. Format log: `/tmp/lunamo-split-final-format.log` (empty, exit 0). No claim is made that 465 requirements themselves passed manual acceptance. The latest source still needs a fresh artifact build and packaged/native acceptance.

## Consolidated local gates — 2026-09-09

Current structured candidate passes development artifact verification and automatic performance (launch p95 340.94 ms, RSS 204.41 MiB, scroll max 73.23 ms). The exact CI-equivalent local command `sh Tools/verify-current-gates.sh` completed with exit 0 (`/tmp/lunamo-final-all-gates.log`); remote CI has not been run. Logs are preserved alongside the candidate in its verification directory.

QA ZIP SHA-256 is d23fb9bf7500e34483b13ba89dbcbdf9ddea890483891e897178b96508ea4484. Its generated checklist retains all 23 manual-only entries pending. `NativeAcceptance.md` specifies reproducible manual cases; it is not a completed acceptance record. The latest exact-app capture reports Mac locked, while earlier unlocked attempts failed with ScreenCaptureKit -3811. Developer ID/notarization and clean-host acceptance remain outstanding.

## Native acceptance resumed — 2026-09-09

Computer Use recovered for the exact structured candidate. Started from a blank notebook. Observed ordinary and Japanese ValueError, SyntaxError, NameError, ZeroDivisionError and missing-module error with an error icon (not a success checkmark). Details was toggled ten times for the ordinary ValueError, NameError, zero division and missing module; Japanese traceback was expanded and its text read. SyntaxError renders inline without a traceback disclosure. Each of the failure types was followed by successful `40 + 2` execution; a full-size screenshot showed output 42. This is partial completion of the longer NativeAcceptance procedure, not its two complete repeated matrices.

Actual `os._exit(17)` terminated Python while the app and editor remained available. The UI stayed Running; Notebook > Restart Kernel remained available, preserved edited `40 + 2`, cleared transient output and did not execute it. Explicit Run succeeded. Saved through the real Save As panel to `/tmp/lunamo-native-qa.OF3PQR/recovered.py`; on-disk source contains `40 + 2`. Added unsaved `40 + 3`, attempted quit, cancelled and observed the edit retained, then discarded only that disposable edit and quit.

Observed gaps requiring follow-up:

1. Missing-package banner persisted after removing the import, successfully executing `40 + 2`, and restarting the kernel. No package installation was performed.
2. Output 42 was visible, but AX exposed only `Native HTML output`, losing the result's readable value.
3. After relaunch, the Open panel selected the saved recovered.py yet reported Open disabled. Keyboard selection also showed the row selected. A subsequent local UTType check found both the extension and file content type are public.python-script, matching the allowed type. The cause is **unresolved** (app, platform or automation); do not label this a proven type-filter defect. The panel was cancelled and the empty app quit. Native reopen acceptance is not complete.

Clipboard automation intermittently timed out; direct setValue followed by explicit execution worked. An attempted combined process/source inspection was stopped before execution by ToolUseProxy deadline expiration. A later narrow source read and file-type probe succeeded; no protection configuration was changed. Small blank screenshots sometimes returned for the Open panel, so visual acceptance of that panel is unavailable.

## Package-alert candidate verification — 2026-09-09

Built `.build/package-alert-candidate-20260909/Lunamo.app` from the runtime source that
tracks kernel package-alert provenance and supplies native output accessibility values.
The complete local gate passed with 196 unit, 43 integration and 8 contract tests. A
real-sidecar failure-matrix assertion now requires the missing-package prompt to appear for
the missing import and disappear after a successful rerun. Development artifact verification
passed for 20 nested Mach-O files, fixed sidecar contracts and the external-network-denied
packaged flow.

The exact candidate was selected by its full app path to avoid attaching Computer Use to a
simultaneously running older candidate. A missing import produced an error icon, package
prompt and readable exception. Replacing it with `40 + 2` removed the package prompt and
exposed `Native HTML output, Value: 42` through accessibility. A Japanese ValueError then
survived ten Details open/close cycles, followed by a successful rerun and accessible 42;
the app remained alive.

The saved `/tmp/lunamo-native-qa.OF3PQR/recovered.py` reopened through the native Open panel.
The previous disabled state was caused by incomplete row selection: path navigation selected
the directory entry, and explicit file-row selection enabled Open. Both invisible panel
resize handles also worked. With both side panels open at the constrained test width, the
assistant was at its 280-point minimum; reducing the left panel created width budget and the
assistant then expanded to 360 points without a visible divider or crash.

Current-candidate performance passed: cold-window p95 349.08 ms over 20 launches,
app/sidecar RSS 192.20 MiB, maximum 100-cell/50-MiB-image scroll delay 75.34 ms and maximum
synchronous layout 44.78 ms. QA ZIP SHA-256 is
`c69a133941f1173830d1373649d4a2730ddb25f75e3fb24ecacb04cdbcd1dfbd`; all 23 manual-only
checklist entries remain pending. This development-signed evidence does not establish
Developer ID distribution, notarization, the complete two-pass manual matrix or clean-host
offline acceptance.
