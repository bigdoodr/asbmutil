#!/bin/bash
#
# Build, sign, notarize and staple the macOS release artifacts (runs on a macOS runner).
#
#   dist/signed/ASBMUtil-<version>.pkg              signed with Developer ID Installer, notarized, stapled
#   dist/signed/ASBMUtil-<version>.dmg              signed, notarized, stapled
#   dist/signed/asbmutil-<version>-macos-arm64.zip  signed CLI, notarized (a bare binary can't be stapled)
#   dist/signed/SHA256SUMS
#
# The .app is signed and notarized once and stapled; the pkg and dmg are then built from THAT app. Don't
# call `make create-pkg` / `make create-dmg` here: create-app-bundle deletes and rebuilds dist/ASBMUtil.app,
# which would discard the signature and stapled ticket.
#
# Environment:
#   VERSION            release version without the leading "v" (the same value release.yml uses)
#   KEYCHAIN           keychain holding the Developer ID Application and Installer identities (unlocked)
#   NOTARY_PROFILE     notarytool keychain profile stored in that keychain (see .github/workflows/signed-release.yml)
#
# Usage: VERSION=2026.11.06.1500 KEYCHAIN=... NOTARY_PROFILE=... tools/ci-sign-release.sh

set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${KEYCHAIN:?KEYCHAIN is required}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE is required}"

repoRoot="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "${repoRoot}"

out="dist/signed"
app="dist/ASBMUtil.app"
pkg="${out}/ASBMUtil-${VERSION}.pkg"
dmg="${out}/ASBMUtil-${VERSION}.dmg"
zip="${out}/asbmutil-${VERSION}-macos-arm64.zip"

# Use the certificates' common names ("Developer ID Application: Name (TEAMID)").
identities="$( security find-identity -v "${KEYCHAIN}" )"
APP_ID="$( sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' <<<"${identities}" | head -1 )"
PKG_ID="$( sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' <<<"${identities}" | head -1 )"
[[ -n "${APP_ID}" ]] || { echo "::error::No 'Developer ID Application' identity in ${KEYCHAIN}"; exit 1; }
[[ -n "${PKG_ID}" ]] || { echo "::error::No 'Developer ID Installer' identity in ${KEYCHAIN}"; exit 1; }
echo "Signing as: ${APP_ID}"
echo "Packaging as: ${PKG_ID}"

notarize() {  # <file>
    local file="${1}" result status id
    echo "Notarizing ${file} (this can take several minutes)..."
    result="$( xcrun notarytool submit "${file}" --keychain-profile "${NOTARY_PROFILE}" --keychain "${KEYCHAIN}" \
        --wait --output-format json )" || true
    status="$( jq -r '.status // "Unknown"' <<<"${result}" )"
    id="$( jq -r '.id // empty' <<<"${result}" )"
    if [[ "${status}" != "Accepted" ]]; then
        echo "::error::Notarization of ${file} finished as '${status}'"
        [[ -n "${id}" ]] && xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" --keychain "${KEYCHAIN}" || echo "${result}"
        exit 1
    fi
    echo "${file}: Accepted (${id})"
}

rm -rf "${out}" dist/ASBMUtil.app
mkdir -p "${out}"

# 1. Build and sign the binaries and the app bundle with the existing Makefile targets
#    (these set the edu.wku.* identifiers, hardened runtime and timestamp).
make swift-build compile-icon sign-binaries create-app-bundle sign-app \
    VERSION="${VERSION}" SIGNING_IDENTITY_APP="${APP_ID}"

# 2. Notarize and staple the app
ditto -c -k --keepParent "${app}" dist/ASBMUtil-notarize.zip
notarize dist/ASBMUtil-notarize.zip
rm -f dist/ASBMUtil-notarize.zip
xcrun stapler staple "${app}"

# 3. Installer package (built from the stapled app)
staging="$( mktemp -d )"
cp -R "${app}" "${staging}/"
chmod +x scripts/postinstall
pkgbuild \
    --root "${staging}" \
    --install-location /Applications \
    --scripts scripts \
    --identifier edu.wku.asbmutil.pkg \
    --version "${VERSION}" \
    --sign "${PKG_ID}" --keychain "${KEYCHAIN}" --timestamp \
    "${pkg}"
rm -rf "${staging}"
notarize "${pkg}"
xcrun stapler staple "${pkg}"

# 4. Disk image
hdiutil create -volname "ASBMUtil" -srcfolder "${app}" -ov -format UDZO "${dmg}"
codesign --force --sign "${APP_ID}" --keychain "${KEYCHAIN}" --timestamp "${dmg}"
notarize "${dmg}"
xcrun stapler staple "${dmg}"

# 5. CLI zip (the CLI binary was signed by sign-binaries)
zip -j "${zip}" .build/release/asbmutil
notarize "${zip}"

# 6. Verify everything before anything is published
echo "Verifying..."
codesign --verify --deep --strict --verbose=2 "${app}"
spctl --assess --type execute -vv "${app}"
xcrun stapler validate "${app}"
pkgutil --check-signature "${pkg}"
spctl --assess --type install -vv "${pkg}"
xcrun stapler validate "${pkg}"
codesign --verify --verbose=2 "${dmg}"
xcrun stapler validate "${dmg}"
codesign --verify --verbose=2 .build/release/asbmutil

( cd "${out}" && shasum -a 256 -- * > SHA256SUMS )
echo "Signed artifacts:"; ls -la "${out}"
