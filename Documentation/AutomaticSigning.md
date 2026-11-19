# GitHub Actions signing

`Release Candidate` builds a candidate on a `v*` tag or manual dispatch. It does
not replace an existing GitHub Release or publish its appcast. Download the
`Lunamo-notarized` Actions artifact for qualification before publishing a new
version.

## Repository secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the selected Developer ID Application identity, including its private key |
| `DEVELOPER_ID_P12_PASSWORD` | Random password protecting that PKCS#12 export |
| `DEVELOPER_ID_APPLICATION` | Exact Developer ID Application identity name |
| `SPARKLE_PRIVATE_KEY` | Existing Sparkle key matching `SUPublicEDKey`; never generate a replacement during setup |
| `NOTARY_APPLE_ID` | Apple Developer account used for notarization |
| `NOTARY_APP_PASSWORD` | Apple app-specific password, not the Mac login password |
| `NOTARY_TEAM_ID` | Developer team owning the signing certificate |

Secrets are registered with `gh secret set` via standard input, never committed.
Export only the intended Developer ID identity, not all identities in the login
keychain. Delete local exported private-key files once registration succeeds.
Apple app-specific passwords must be entered locally in a hidden prompt; never
paste them into a chat, issue, or workflow log.

The runner imports the identity into a temporary keychain and creates a notarytool
profile. It builds and signs the app, measures release performance, notarizes and
staples the app and DMG, then signs the Sparkle feed. An always-running cleanup
step deletes the signing keychain and temporary exported key files. Artifacts
include only the DMG, appcast, notarization results, and manual acceptance checklist.

## CI measurements

Functional tests run in debug configuration. The two `PerformanceTests` budgets
run separately in release configuration, avoiding concurrent integration-test
work during wall-clock measurements and measuring optimized application code.
The 16 ms typing and 100 ms dispatch p95 limits are unchanged. Sidecar integration
performance tests and packaged-app acceptance remain enabled.

## Verification

Record the successful CI and Release Candidate run URLs, candidate checksums and
notarization acceptance results after each workflow change. A successful workflow
produces a candidate; it does not establish clean-host or update-install acceptance
for a newly built binary.

## Initial setup — 2026-11-19

The seven secrets above were registered for `mani1261790/Lunamo` using the
existing Developer ID identity and Sparkle key. Apple ID notarization credentials
were validated with Apple before registration. Temporary local private-key exports
were deleted. No certificate or Sparkle key rotation was performed.

- [CI verification after formatting fix](https://github.com/mani1261790/Lunamo/actions/runs/44522912996)
- [First fully configured Release Candidate execution](https://github.com/mani1261790/Lunamo/actions/runs/44523500129)

Follow these run links for their final status and generated artifacts. They were
started during setup; this record alone is not a success assertion. The public
0.1.2 release remains the locally verified artifact documented in Release-0.1.2.md.

## Physical-Mac qualification before publication

The hosted runner's full-app performance measurement is reference information;
its result and log remain in the workflow summary and `HostedPerformance.log`.
It does not block signed/notarized **candidate** generation. Functional tests,
focused optimized performance tests, signatures, license checks and notarization
remain blocking. The 100 ms scroll limit is unchanged.

Before publication, measure the actual final DMG on a physical Apple Silicon Mac:

```sh
.build/Sidecar/bin/python3 -I Tools/qualify-physical-performance.py \
  --artifact /absolute/path/Lunamo-VERSION.dmg \
  --output /absolute/path/PhysicalPerformance.json \
  --checklist /absolute/path/ReleaseChecklist.yml
```

The command validates the DMG staple, copies its app to temporary storage,
verifies the signature, runs the unchanged performance thresholds, and records
hardware/OS, timestamp, measurements and the DMG SHA-256. It rejects virtual
hosts and does not overwrite existing reports. The checklist is linked to the
report only after a passing measurement. Complete the remaining manual checks,
then run the existing publication gate:

```sh
.build/Sidecar/bin/python3 -I Tools/verify-requirements.py --all-must \
  --release-checklist /absolute/path/ReleaseChecklist.yml \
  --artifact /absolute/path/Lunamo-VERSION.dmg
```

That gate now requires a physical performance report, validates its checksum and
numeric limits independently, and also requires every existing manual check.
A green candidate workflow does not authorize publishing an unqualified artifact.
