# Keys

Public material only. Private keys never enter this repository.

| File | What |
|---|---|
| `root-keyid.txt` | key id of the offline root; platforms pin it |
| `keyset.dsse.json` | the key set the root signed: which online key may sign the feed, valid at most 180 days, version only grows |
| `rotate.sh` | makes a new online key and a new key set, and sets the secret |

The online signing key is the secret `VULNFEED_SIGNING_KEY` of the `publish`
environment of this repository. Secrets cannot be copied between repositories,
so it must be set here by the maintainer (steps below). The first job of the
publish workflow fails with a clear message until it is set; nothing is ever
published unsigned.

## Owner steps (once)

The `publish` environment (deployments limited to `main`) already exists if the
setup commit says so; check with
`gh api repos/openctemio/vulnfeed-bundles/environments/publish --jq .deployment_branch_policy`.
If not, create it: Settings, Environments, New environment `publish`, Deployment
branches: Selected branches, add `main`.

Then one of:

**A. You still have the online key file (`signing.key`) that matches the current key set**

```sh
gh secret set VULNFEED_SIGNING_KEY --env publish --repo openctemio/vulnfeed-bundles < signing.key
```

then delete `signing.key` from the machine.

**B. You do not have it (the usual case: it was deleted after the first setup).**
Use the offline root to sign a new key set that trusts a fresh online key. On the
machine that holds `root.key` (Go and an authenticated `gh` needed):

```sh
git clone git@github.com:openctemio/vulnfeed-bundles.git && cd vulnfeed-bundles
git checkout -b keys/rotate-v2
bash keys/rotate.sh /path/to/root.key
git add keys/keyset.dsse.json && git commit -m "keys: key set v2" && git push origin keys/rotate-v2
gh pr create --fill
```

`rotate.sh` generates the new online key in a temporary directory, signs the
key set with a version one higher than the current one, checks that the new set
names the root in `root-keyid.txt`, stores the private key as
`VULNFEED_SIGNING_KEY` in the `publish` environment and deletes it from disk.
Merge the pull request: the next hourly run signs with the new key. Platforms
accept the higher version and refuse the old key set from then on.

**Optional, both cases:** a free NVD API key makes a from-scratch build fast
(incremental runs do not need it):

```sh
gh secret set NVD_API_KEY --repo openctemio/vulnfeed-bundles
```

Run the workflow once to check: `gh workflow run publish.yml --repo openctemio/vulnfeed-bundles`.

## Routine rotation

The key set is valid for at most 180 days; the workflow warns 30 days before it
ends and fails when it has ended. Repeat case B (`rotate.sh`) before then. If the
online key may have leaked, do it at once.

If the root itself is compromised, generate a new root (`vulnfeed keys root-init`)
and have every platform pin its new key id; see the vulnfeed `keys/README.md`.
