# Native acceptance for Lunamo

This is a procedure, **not a completed test record**. Record the exact app/archive hash,
OS version, tester, date, and observed results. Use a disposable notebook in a dedicated
QA folder. Managed-environment deletion/rebuild checks belong on a dedicated test account
or clean test host, not an existing working Python environment.

## Error and recovery sequence

1. Launch the exact candidate app. Create a new notebook in the QA folder and select the
   bundled Python. Authorize Run Once when requested.
2. Execute each source below separately. After each failure, inspect the cell's error
   indicator, error text and accessibility tree. Expand/collapse Details ten times, then
   replace the source with `40 + 2` and execute. Require output 42 and a successful indicator.
   A finished/idle session alone does not establish success.

   ```python
   if True print('invalid')
   ```

   ```python
   lunamo_undefined_name
   ```

   ```python
   1 / 0
   ```

   ```python
   import lunamo_nonexistent_dependency_93d1
   ```

   ```python
   raise ValueError('日本語の検証エラー')
   ```

3. Repeat the entire sequence twice. App must stay alive; no stuck spinner, success
   checkmark on an error, unreadable traceback, or lost edits. Record new crash reports,
   including their timestamps, if any appear. This checks recurrence; it does not claim
   deterministic reproduction of the original accessibility recursion crash.
4. In three cells, place `downstream = upstream + 1` followed by `downstream` above
   `upstream = 1 / 0`; put `42` in the third cell. Run All: independent output is 42 and the
   dependent cannot succeed. Change the ancestor to `upstream = 40`, execute it, and require
   downstream output 41.
5. Execute `while True: pass`, interrupt, and confirm editing/restart remains available.
   In the disposable notebook only, execute `import os; os._exit(17)` to terminate Python.
   Edit the source to `40 + 2`, explicitly restart the kernel, and verify that restart
   itself does not execute the edited cell. Explicit Run then produces 42.
6. Save As into the QA folder, close, reopen, and compare cell source. Results should not
   be treated as live across a restarted session. Quit with one additional unsaved edit:
   verify the save/discard/cancel guard, cancel once and confirm the edit remains.

## Native interactions

- Cell surface: grab cursor. Delete/duplicate/assistant chips: pointer. Code editor: text
  cursor. During cell reorder: closed hand. On drop, moving into the editor, hiding a cell,
  leaving the window and returning, the cursor must not remain stuck or flicker repeatedly.
- Scroll a 100-cell notebook while a cell has a selection/caret. Confirm selection and
  focus remain correct after scrolling away and back, editing and undoing.
- Resize the window and each panel boundary with an error expanded. Controls remain
  reachable; divider hit regions and cursor work; no constraint-loop crash.
- Inspect VoiceOver/accessibility names for the execution button, error container and
  Details. Check both light/dark and increased-contrast/reduced-transparency configurations
  on the dedicated test host. Restore host settings after testing.

## Managed environment checks on the dedicated host

Use throwaway workspaces A/B. Verify project/shared environment selection persists after
relaunch and switching A does not change B. For rebuild, Trash and cache cleanup, inspect
confirmation text and target scope, cancel once, and verify nothing changed. Confirm the
operation only on disposable QA environments; verify unaffected environments still run.

## Evidence

For each section record pass/fail, actual observations, app hash, and any crash/trace file.
A tool capture error or unavailable clean host is **not verified**, never a pass. Developer
ID signing, notarization and clean-host offline installation are separate requirements in
`ReleaseVerification.md`.
