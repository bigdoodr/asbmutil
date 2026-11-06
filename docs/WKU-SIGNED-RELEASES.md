# Signed and notarized releases

The upstream `Release` workflow builds **unsigned** macOS artifacts. After it finishes for a `v*` tag,
[Signed Release](../.github/workflows/signed-release.yml) rebuilds the macOS artifacts with WKU's Developer ID
certificates, has Apple notarize them, and replaces the unsigned assets on the same release:

| Asset | Signed with | Notarized |
|---|---|---|
| `ASBMUtil-<version>.pkg` | Developer ID **Installer** | yes, stapled |
| `ASBMUtil-<version>.dmg` | Developer ID Application | yes, stapled |
| `asbmutil-<version>-macos-arm64.zip` (CLI) | Developer ID Application | yes (a bare binary can't be stapled) |
| `SHA256SUMS` | | |

The Linux tarball is unchanged. Signing lives in its own workflow, and `tools/ci-sign-release.sh`, so
`release.yml` stays identical to upstream and upstream syncs don't conflict with it.

It runs automatically for every release the upstream-sync PR produces, and can be run by hand for any
existing release tag: **Actions → Signed Release → Run workflow**.

## One-time setup

1. **Create the environment.** Settings → Environments → New environment → `release-signing`.
   - Add yourself under *Required reviewers* so every signing run waits for your approval.
   - Under *Deployment branches and tags*, select *Selected branches and tags* and allow only `main`.
2. **Export the certificates** from Keychain Access (expand each certificate so its private key is
   included, right-click → Export → `.p12`, set a password):
   - `Developer ID Application: …`
   - `Developer ID Installer: …`

   Then base64-encode each: `base64 -i cert.p12 | pbcopy`.
3. **Create an app-specific password** at account.apple.com → Sign-In and Security → App-Specific Passwords.
4. **Add these as secrets of the `release-signing` environment:**

   | Secret | Value |
   |---|---|
   | `APPLE_APP_CERT_P12_BASE64` | base64 of the Application certificate `.p12` |
   | `APPLE_APP_CERT_P12_PASSWORD` | its export password |
   | `APPLE_INSTALLER_CERT_P12_BASE64` | base64 of the Installer certificate `.p12` |
   | `APPLE_INSTALLER_CERT_P12_PASSWORD` | its export password |
   | `NOTARY_APPLE_ID` | Apple ID of the developer account |
   | `NOTARY_APP_SPECIFIC_PASSWORD` | the app-specific password |
   | `NOTARY_TEAM_ID` | the 10-character Team ID |

   Environment secrets are only given to jobs that use that environment, so the sync and CI workflows never see them.
5. **Try it** on an existing release: Actions → Signed Release → Run workflow, with that release's tag.

## Safeguards

- Only tags whose commit is on `main` get signed.
- The Apple ID credentials are checked right after import, before the (long) build.
- Notarization must finish `Accepted` for each artifact, and the signatures, Gatekeeper assessment and
  stapled tickets are verified, before anything is uploaded. A failure leaves the unsigned assets in place.
- The certificates live in a temporary keychain that is deleted at the end of the job.

## Things to know

- The Team ID is whatever the certificates belong to. If it ever changes, anything on the Macs that was
  written against the old Team ID (Mosyle PPPC, login-item or background-task rules) must be updated.
- Saved credentials: the app stores them in the data-protection keychain, which is scoped by signing
  identity. Moving from unsigned or differently signed builds to these may mean re-entering ABM/ASM credentials once.
- Not tested on a real runner when written: the first run may need adjustments. Use *Run workflow* with a
  tag and watch the log before relying on it.
