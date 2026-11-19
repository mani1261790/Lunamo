# Lunamo 0.1.2 release verification — 2026-11-19

- Built from the isolated public-release checkout; unrelated development changes were not included.
- Version 0.1.2, build 4. Original code MIT; third-party licenses and source availability preserved.
- App Developer ID signature, Hardened Runtime and 20 nested Mach-O signatures verified.
- Final app notarization: 867ad901-d501-4319-9fb7-43c2a18fe7b4 — Accepted; ticket stapled and validated.
- DMG notarization: d10e2610-4cad-4929-986d-540d16ca5c0a — Accepted; ticket stapled and Gatekeeper assessment accepted.
- DMG SHA-256: `dc286c69b78a922e8419315736b49dc0fc87cb276df7fdca6a11740d43569de7`.
- `verify-licenses.py`: complete packaged notices, source links, renderer hashes and all 44 Python distributions passed. Deliberate missing/truncated notice failures were detected.
- Native menu inspected: Lunamo → Licenses… opened the local bundled HTML in Safari, with MIT scope, third-party texts and source availability links. All links resolve offline except explicit upstream source downloads.
- Packaged application acceptance: open, edit, save, Python selection, trust, execute, output 43, process cleanup; external network denied.
- Sparkle 0.1.1 (build 3) → 0.1.2 (build 4) installed successfully using a signed loopback candidate feed. Updated executable and Info.plist match the final app, notices verify, signature and staple validate, and the notebook SHA-256 stayed unchanged. Updated app acceptance passed again.
- Production appcast points to the v0.1.2 HTTPS GitHub asset and was signed by generate_appcast. Candidate and production enclosures have the same archive Ed25519 signature and size. Published release: https://github.com/mani1261790/Lunamo/releases/tag/v0.1.2. Public appcast bytes match the generated feed, and GitHub reports the same DMG SHA-256 as above. A fresh disposable 0.1.1 installation updated to 0.1.2 using its default public feed (no feed override); installation finished, packaged license verification, signature and staple validation passed, and the notebook checksum remained unchanged.
- LP: removed Apple logo/Dock raster/device shell; preserved actual app screenshots and original backdrop. PC/mobile, Japanese/English, screenshot alignment, scroll pin/release/reverse, and license-link navigation checked. Exact alignment delta was 0px; no horizontal overflow or JavaScript errors observed.

Technical audit scope and compatibility rationale: [ThirdPartyLicenses.md](ThirdPartyLicenses.md). The first 0.1.2 app notarization was superseded after adding nested Tcl/Tk notices; only the final artifact above is intended for publication.

## Publication verification

- GitHub Pages run 44515289842 succeeded. The live LP download points to 0.1.2, and its footer opens the published license page with the expected notices. Browser navigation verified. The license page requests a missing root favicon (404); content and notice navigation are available.
- GitHub recognizes the original-code license as MIT.
- Tag-triggered Release Candidate run 44515348116 stopped at required-secret validation: `Missing SPARKLE_PRIVATE_KEY`. The signing/notary secret environment entries were also empty. Hosted automatic signing remains unconfigured; the published artifacts were instead signed, notarized and verified locally as documented above. No private keys were exported or uploaded.
- General CI run 44515289794 was still running its Implemented gates step at the time of this record; its pinned sidecar build passed. This is not a claim that hosted CI has passed.
