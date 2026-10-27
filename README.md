# vulnfeed-bundles

The signed vulnerability feed of [OpenCTEM](https://github.com/openctemio/openctem).
This repository holds no application code. Its releases are the feed; a
workflow builds, signs, verifies and publishes a new release every hour using
the collector in [openctemio/vulnfeed](https://github.com/openctemio/vulnfeed).

## What is here

| Path | What |
|---|---|
| Releases | the feed: tag `v1-N` = bundle format v1, sequence N (only grows); the title carries the UTC date and time |
| `.github/workflows/publish.yml` | the hourly build, sign, verify and publish |
| `keys/` | public key material: `root-keyid.txt` (the offline root's key id), `keyset.dsse.json` (the key set the root signed), rotation steps |
| `NOTICE` | the terms of the data sources |

## How platforms use it

An OpenCTEM platform downloads
`https://github.com/openctemio/vulnfeed-bundles/releases/latest/download/latest.dsse.json`
and the files that pointer names, verifies them against the root key id it
pins and imports them. This is the default of the platform; override it with
`VULNFEED_BASE_URL` (an internal mirror, or the older
`https://github.com/openctemio/vulnfeed/releases`, which is kept as a copy for a
transition period). Air-gapped use and checking an import:
[Vulnerability and program feeds](https://docs.openctem.io/operations/feeds/).
Formats and the trust model (offline root, key sets, rollback and freeze
protection): see the [vulnfeed README](https://github.com/openctemio/vulnfeed#readme)
and [SECURITY.md](https://github.com/openctemio/vulnfeed/blob/main/SECURITY.md).

## Verify a release yourself

```sh
git clone https://github.com/openctemio/vulnfeed && cd vulnfeed
go build -o vulnfeed ./cmd/vulnfeed
gh release download --repo openctemio/vulnfeed-bundles --dir bundle
./vulnfeed verify --dir bundle --root-key-id "$(curl -fsSL https://raw.githubusercontent.com/openctemio/vulnfeed-bundles/main/keys/root-keyid.txt)"
```

## How it is published

- The workflow pins the collector to one reviewed commit or release of
  openctemio/vulnfeed (`VULNFEED_REF` in the workflow); moving it is a pull
  request here.
- The build job reads the public sources and never sees the signing key.
  The publish job runs in the `publish` environment (only `main` may deploy
  to it), signs with `VULNFEED_SIGNING_KEY`, verifies as a platform would and
  uploads with this repository's own token. No other repository's credentials
  are used.
- The previous release is read from this repository so the sequence continues;
  the very first run, when this repository has no release, continues from the
  last release of openctemio/vulnfeed. The sequence never restarts: platforms
  refuse a lower sequence.
- Nothing is published unsigned: while the signing key is not set the workflow
  fails at its first job with a message saying so.

Maintainers: setting the signing key and rotating it are in
[keys/README.md](keys/README.md).

## Licence

The workflow and scripts are Apache-2.0 (`LICENSE`). The data keeps its
sources' terms, see `NOTICE`. This product uses data from the NVD API but is
not endorsed or certified by the NVD. CVE records from the CVE List of the CVE
Program; CVE is a registered trademark of The MITRE Corporation.
