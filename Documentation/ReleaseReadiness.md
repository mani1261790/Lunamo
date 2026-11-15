# Lunamo release readiness

Status: **NOT approved for public distribution**. Last audit: 2026-09-09.

The current runtime source is included in the development candidate below. Runtime
package-alert cleanup and native HTML accessibility values are covered by unit, real-sidecar,
packaged-flow and exact-app checks. Test and documentation changes made after the build do
not change the candidate binary.

## Current development candidate

- App: `.build/package-alert-candidate-20260909/Lunamo.app`
- QA archive: `.build/package-alert-candidate-20260909/Lunamo-development-QA.zip`
- ZIP SHA-256: `c69a133941f1173830d1373649d4a2730ddb25f75e3fb24ecacb04cdbcd1dfbd`
- Pending artifact-bound checklist: `.build/package-alert-candidate-20260909/ReleaseChecklist.yml` (23 manual-only entries).

This is development-signed, not Developer ID signed or notarized. Older audit artifacts
are historical and must not replace this candidate's evidence.

| Area | Current evidence | Status |
| --- | --- | --- |
| Release tests | 196 unit + 43 integration + 8 contract tests (247 total) | Pass |
| CI-equivalent local command | `sh Tools/verify-current-gates.sh`, including build/tests, full strict formatting, source policy, protocol lock, requirement mapping and offline packaged flow | Pass locally; remote CI not claimed |
| Error recovery | Five real exceptions/reruns, dependency branch isolation and output 41/42, kernel exit, restart retry, stale event rejection, edit/save preservation | Automated checks pass |
| Native error UI | Current candidate: missing-module and Japanese ValueError, Details stress, correction, success indicator and accessible 42; preceding candidate covered the wider five-error matrix and kernel exit | Partial pass; full repeated matrix remains manual |
| Artifact | 20 nested Mach-O signatures, hardened runtime, sidecar contracts, network-denied packaged open/edit/save/trust/run/output/cleanup | Pass in development mode |
| Performance | Current candidate: launch p95 349.08 ms (20 runs), RSS 192.20 MiB, scroll max 75.34 ms, layout max 44.78 ms | Automatic probe passes; manual long-scroll interaction still required |
| Source policy | Oversized files split by responsibility; all source and strict formatting checks pass | Pass |
| Requirement inventory | 465 mandatory IDs mapped, including suffixed IDs | Mapping validation only |
| Screen access | Exact candidate was selected by full app path and inspected through native accessibility and screenshots | Partial native evidence available |
| Distribution | Only Apple Development identity found at last inspection | Developer ID/notarization pending |
| Clean host | Exact notarized archive installed offline on macOS 26 arm64 | Pending |

## Remaining acceptance

1. Follow `NativeAcceptance.md` on the exact candidate: error/accessibility cycles,
   cursor/focus/reorder/resize interactions, and disposable managed-environment operations.
   A procedure or unavailable capture is not a passing observation.
2. Obtain Developer ID/notarization capability and produce the final distribution artifact.
3. Run offline acceptance on a clean supported host, record actual results and complete
   the checklist against that final archive's SHA-256.

The original accessibility crash was not deterministically reproduced. Automated passing
results do not establish its complete elimination or close native acceptance. Performance
probes are in-app measurements, not observation of an unlocked visible UI. Do not weaken
signature protections or mark pending checklist entries passed to bypass these gates.

Historical experiments and limitations: `ErrorHandlingVerification.md`.

## Resolved native findings in this candidate

- The runtime missing-package banner disappears after the failed import is replaced and the cell succeeds; it remains while an execution error remains.
- Native HTML text output exposes its content as the accessibility value; output 42 was observed as `Native HTML output, Value: 42`.
- The saved `recovered.py` opened successfully. In the previous attempt the Open panel row had not completed selection; after path navigation and explicit row selection, Open became enabled.
- Both invisible panel resize regions worked. At a constrained window width the assistant correctly remained at its minimum until the left panel was reduced; it then expanded from 280 to 360 points without a visible divider or crash.

The complete repeated manual matrix, cursor-shape observation, long interactive scroll,
managed-environment destructive checks, Developer ID/notarization and clean-host acceptance
remain open. Details and the disposable test path are in `ErrorHandlingVerification.md`.
