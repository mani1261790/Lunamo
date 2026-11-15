# Release verification

Gate F requires both automated artifact checks and observations that must be made on the
exact notarized archive. A pending checklist is produced beside every release candidate;
`pending` is deliberately a failing state and must never be interpreted as acceptance.

## Automated release candidate

1. Run `Tools/build-release-app.sh` with `MARIMONATIVE_CODESIGN_IDENTITY` set to a
   Developer ID Application identity. A full Xcode installation is required; when
   `xcode-select` points at Command Line Tools, the scripts select an installed Xcode or
   require an explicit `DEVELOPER_DIR`.
2. Run `Tools/verify-release-prerequisites.sh` to reject a non-Developer ID identity,
   incomplete Notary API credentials, an insecure private-key mode, or the wrong host.
3. Run `Tools/notarize-release.sh` with App Store Connect notary credentials.
4. For DMG/Sparkle delivery, follow [DMGUpdates.md](DMGUpdates.md) after app notarization. Bind the manual checklist to the final DMG hash.
5. Run `Tools/measure-release-performance.py` against the signed app on an M2 16 GB-class
   Mac.
5. The artifact verifier runs the packaged sidecar with external networking denied while
   preserving localhost IPC. It selects the packaged Python by absolute path, executes a
   sample Notebook, requires output `42`, verifies the selected executable reported by the
   live session, shuts down every session, and waits for the kernel process to disappear.
6. The same verifier launches the packaged app with an isolated home and external networking
   denied. The native app opens a copied marimo fixture, edits and saves it, selects its
   packaged Python, presents and consumes Run Once trust, produces output `43`, and exits
   without leaving app, sidecar, or kernel processes.
7. Generate the checklist with the bundled sidecar Python:

   `.build/Sidecar/bin/python3 -I Tools/create-release-checklist.py --artifact .build/release-artifacts/Lunamo-0.1.0.zip --output .build/release-artifacts/ReleaseChecklist.yml`

## Manual release candidate

Use a clean macOS 26 arm64 VM or dedicated Mac, disconnect networking, install the exact
ZIP, and complete every pending checklist entry. Each note must state the observed result,
not an intended procedure. Record the executor and an ISO-8601 timestamp with timezone.
The required checks include native hierarchy and accessibility inspection, the 100-cell
50 MiB image-output scroll trace, app/sidecar/kernel process cleanup, Python environment
selection, and offline open, edit, save, and execution.

The checklist is accepted only when its recorded SHA-256 matches the actual archive:

`.build/Sidecar/bin/python3 -I Tools/verify-requirements.py --all-must --release-checklist .build/release-artifacts/ReleaseChecklist.yml --artifact .build/release-artifacts/Lunamo-0.1.0.zip`

Attach the completed checklist, Instruments trace, notary JSON, and final command output to
the release record. A missing Developer ID identity, notary credential, clean macOS 26
host, completed entry, or matching hash blocks MVP acceptance.


## Local pre-distribution evidence (2026-09-08)

External-network-denied acceptance passed on the packaged debug app and sidecar. The Release build is also checked using the installed development identity. Neither a development certificate nor an ad-hoc signature establishes Developer ID distribution/notarization acceptance. Ad-hoc hardened Python failed library validation when loading msgspec; do not bypass library validation to make this check pass.

The mandatory-requirement enumerator now includes IDs ending in a letter. Environment-management cleanup requirements ENV-019A/B are explicit manual release checklist items. Passing the evidence-mapping validator does not complete those items.
