#!/usr/bin/env bash
# Usage: keys/rotate.sh ROOT_SEED_FILE
# Makes a new online signing key, signs a key set that trusts only it (version
# = current + 1) with the offline root, writes keys/keyset.dsse.json and stores
# the private key as VULNFEED_SIGNING_KEY in the `publish` environment.
# Run from a checkout of this repository, on the machine that holds the root.
set -euo pipefail
root=${1:?path to the offline root seed file (root.key)}
repo=${REPO:-openctemio/vulnfeed-bundles}
here=$(cd "$(dirname "$0")" && pwd)
ref=${VULNFEED_REF:-$(sed -n 's/^  VULNFEED_REF: *\([0-9a-fA-Fv.]*\).*/\1/p' "$here/../.github/workflows/publish.yml")}
[ -n "$ref" ] || { echo "VULNFEED_REF not found in the workflow" >&2; exit 1; }
vf() { if [ -n "${VULNFEED_BIN:-}" ]; then "$VULNFEED_BIN" "$@"; else GOFLAGS=-mod=mod go run "github.com/openctemio/vulnfeed/cmd/vulnfeed@$ref" "$@"; fi; }

payload() { python3 -c 'import json,base64,sys; print(json.dumps(json.loads(base64.b64decode(json.load(open(sys.argv[1]))["payload"]))))' "$1"; }
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }

cur=$(field "$(payload "$here/keyset.dsse.json")" version)
new=$((cur + 1))
tmp=$(mktemp -d)
trap 'find "$tmp" -delete' EXIT
umask 077
pub=$(vf keys gen --out "$tmp/signing.key" | sed -n 's/^public key: *//p')
[ -n "$pub" ] || { echo "no public key printed" >&2; exit 1; }
vf keys sign-keyset --root "$root" --key "$pub" --version "$new" --days 180 --out "$tmp/keyset.dsse.json"
got=$(field "$(payload "$tmp/keyset.dsse.json")" root_keyid)
want=$(tr -d '[:space:]' < "$here/root-keyid.txt")
[ "$got" = "$want" ] || { echo "the root file is not the pinned root ($got, want $want): nothing changed" >&2; exit 1; }
gh secret set VULNFEED_SIGNING_KEY --env publish --repo "$repo" < "$tmp/signing.key"
cp "$tmp/keyset.dsse.json" "$here/keyset.dsse.json"
echo "key set version $new written to keys/keyset.dsse.json; secret set in $repo (environment publish). Commit and merge the key set."
