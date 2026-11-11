#!/bin/sh
# Signs a published release's SHA256SUMS with NX's addon key and uploads
# SHA256SUMS.sig beside it. The panel installs or updates over SSH (or on
# its own server) only a release whose install.sh and binary match checksums
# signed by the key that signed its manifest, and the key never goes to CI —
# so run this on the owner's machine once the release workflow is done.
#
#   scripts/sign-sums.sh v0.4.3
#
# Before signing it downloads every asset and refuses unless each one matches
# SHA256SUMS, SHA256SUMS lists every asset, and the release's nx-addon.json
# names the tag's version and is signed by NX. Run again: a release already
# signed is only checked.
set -eu
cd "$(dirname "$0")/.."
REPO="${NX_RELEASE_REPO:-nx-panel/notif}"
TAG="${1:?usage: scripts/sign-sums.sh vX.Y.Z}"
KEY="${NX_ADDON_KEY:-../nx-panel/.secrets/addon_ed25519.key}"
kit() { go run github.com/nx-panel/addon-kit/cmd/nx-addon "$@"; }
sums() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
fail() { echo "sign-sums: $*" >&2; exit 1; }

[ -f "$KEY" ] || fail "no key at $KEY (set NX_ADDON_KEY)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
gh release download "$TAG" -R "$REPO" -D "$dir" || fail "cannot download $REPO $TAG"
[ -f "$dir/SHA256SUMS" ] || fail "$TAG publishes no SHA256SUMS"

if [ -f "$dir/SHA256SUMS.sig" ]; then
	[ "$(kit verify-sums "$dir/SHA256SUMS" "$dir/SHA256SUMS.sig")" = "signed by: NX" ] ||
		fail "$TAG has a SHA256SUMS.sig NX did not make: delete it on GitHub and run again"
	echo "$REPO $TAG: SHA256SUMS already signed by NX"
	exit 0
fi

(cd "$dir" && sums -c SHA256SUMS) || fail "an asset of $TAG does not match its SHA256SUMS"
for f in "$dir"/*; do
	name="$(basename "$f")"
	[ "$name" = SHA256SUMS ] && continue
	awk -v n="$name" '{ sub(/^\*/, "", $2) } $2 == n { found = 1 } END { exit !found }' "$dir/SHA256SUMS" ||
		fail "SHA256SUMS does not list $name"
done
want="${TAG#v}"
have="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dir/nx-addon.json" | head -n 1)"
[ "$want" = "$have" ] || fail "the release's nx-addon.json says $have, the tag is $want"
[ "$(kit verify "$dir/nx-addon.json")" = "signed by: NX" ] || fail "the release's nx-addon.json is not signed by NX"

kit sign-sums -key "$KEY" "$dir/SHA256SUMS" >"$dir/SHA256SUMS.sig"
[ "$(kit verify-sums "$dir/SHA256SUMS" "$dir/SHA256SUMS.sig")" = "signed by: NX" ] || fail "$KEY is not NX's addon key"
gh release upload "$TAG" -R "$REPO" "$dir/SHA256SUMS.sig"
gh release download "$TAG" -R "$REPO" -p SHA256SUMS.sig -O "$dir/served.sig"
cmp -s "$dir/served.sig" "$dir/SHA256SUMS.sig" || fail "the uploaded SHA256SUMS.sig is not the one signed"
echo "$REPO $TAG: SHA256SUMS signed by NX and uploaded"
