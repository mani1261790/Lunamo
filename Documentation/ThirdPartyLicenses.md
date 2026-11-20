# Third-party licensing and release verification

Lunamo's original code is MIT licensed. This grant does not relicense marimo, marimo-lsp, libzmq, uv or any other bundled component. LICENSE and BRAND.md define the original-code and artwork scopes.

## Compatibility decision (2026-11-19)

- marimo-base 0.24.0 and marimo-lsp 0.1.0 retain Apache-2.0. The independent Swift client talks to the sidecar through its protocol. Apache-2.0 sections 1 and 4 permit this distribution with license/attribution/NOTICE retention; Lunamo's original code can be MIT.
- libzmq 4.3.5 and MPL-covered uv dependencies retain MPL-2.0. Covered files' source is available at the exact URLs in Source-availability.txt. MPL sections 3.2 and 3.3 permit differently licensed larger works; Lunamo's MIT does not override these obligations.
- The uv lockfile contains configparser/r-efi with permissive OR alternatives and priority-queue with an MPL alternative. We select MIT/Apache-2.0 or MPL-2.0, not the LGPL alternatives. No mandatory GPL/AGPL license was found in the reviewed dependency metadata. Do not infer license obligations merely from a GPL text present in an unused platform/build dependency's notice.
- certifi's MPL certificate bundle is included in source form with its original notice.

Primary terms: https://www.apache.org/licenses/LICENSE-2.0 and https://www.mozilla.org/en-US/MPL/2.0/ .

## Evidence and coverage

MarimoNative/Resources/Licenses contains full notices, source URLs, immutable checksums and dependency manifests. The app's Lunamo → Licenses… menu opens its local index; the LP footer links the public copy. Source notices are retained with the Python package files too.

The uv inventory intentionally covers all 680 registry packages in uv 0.12.9 Cargo.lock, including unused development and other-platform packages. Every downloaded .crate was checked against the Cargo.lock SHA-256. License files within the crate (including native subdependencies) were collected; where missing, pinned upstream repository files or the declared SPDX standard text plus available author attribution were included. This is a conservative license-notice superset, not a claim that all 680 are linked in the macOS binary. Exact registry source URLs are retained for MPL files.

The Web renderer notice covers a conservative 90-package production dependency closure for Vega 6.4.0, Vega-Lite 6.4.3, Vega-Embed 7.2.0 and KaTeX 0.18.5. npm's integrity-verified archives and frozen dependency resolution are recorded in web-package-lock.json. The shipped upstream minified JS and fonts are unchanged; their hashes are recorded in inventory.json. This over-inclusive closure is not an exact reconstruction of the upstream bundle build graph.

Python native notices come from the same python-build-standalone 20260901 full archive. PYTHON.json marks zlib as system-linked on aarch64-apple-darwin; its generic zlib-ng license entry does not describe a statically shipped zlib-ng library on this target. Upstream full-archive license texts are retained as a platform superset. Hash-verified Tcl/Tk 9.0.4 source archives additionally supply nested license.terms (including Itcl 4.3.8 and Thread) that are not present in the standalone distribution license folder. Python-package inventory covers all 44 distributions in the shipped sidecar.

The LP's custom Apple glyph, Dock raster and CSS device shell have been removed. Its laptop frame is an AI-generated raster asset (lunamo-laptop-generated.png); screenshots show the actual Lunamo app and are overlaid separately. The generated device contains no Apple logo or borrowed Dock artwork. Original icon sources and the Manrope OFL notice are preserved. No trademark search/registration or legal opinion is implied by this technical compliance work.

## Required release checks

`python3 Tools/verify-licenses.py` checks source notice hashes and audited runtime/dependency versions. Pass a packaged `.app` path to check actual bundled copies, renderer hashes, Python distributions and MPL source notices. The release build and artifact verification call this automatically. Xcode and the debug packaging script also copy the license directory.

Missing Sparkle notices and truncated uv notices were each deliberately tested and rejected. When any runtime or vendored renderer changes, refresh the inventory and notices from authoritative source archives before updating checksums. Do not merely bless a failed hash. New dependency families require their own review.

Do not edit a published signed DMG in place. Create a new version, verify it, notarize the app and DMG, sign the Sparkle appcast, and test the old-to-new update.
