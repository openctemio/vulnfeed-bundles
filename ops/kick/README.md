# Publisher scheduler (ops note)

GitHub runs scheduled workflows on a best-effort basis. In November 2026 the
hourly `publish.yml` cron ran about one time in five, with gaps of up to nine
hours, and a three-day publisher failure went unnoticed. Freshness therefore
does not depend on GitHub's cron:

| Layer | Runs where | Does |
|---|---|---|
| `vulnfeed-kick.timer` (this directory) | a host the maintainers run, hourly at :47 | dispatches `publish.yml` when the newest release is 55 minutes old or more and no run is queued; then starts `watch.yml` |
| `watch.yml` | GitHub, after every publish run, every 30 minutes by cron, and on dispatch from the timer | opens the `feed-stale` issue when the newest release is older than 2 hours or the last publish run failed; closes it when healthy; dispatches `publish.yml` when due |
| `publish.yml` cron | GitHub, hourly | the backstop when the timer host is down |

Any one of the three keeps the feed moving, and the alert fires from two
independent schedulers (the timer and GitHub). The alert is a GitHub issue
in this repository: everyone watching the repository is notified when it
opens and when another publish run fails. A failed watch run also fails its
workflow, which GitHub reports to the person who last changed the schedule.

Dispatches never pass inputs, so a scheduler can never override the removal
guard (`allow_mass_change` stays false).

## Install (on a host the maintainers run; not a CI runner)

Do not install it on a self-hosted CI runner host: runners execute pull
request code, which must never be able to read the token. Do not install it
on a platform host either: platforms talk only to their sensors.

1. Token: a fine-grained personal access token, resource owner
   `openctemio`, repository access "Only select repositories" =
   `vulnfeed-bundles`, permissions **Actions: Read and write** (and the
   implied Metadata: Read) and nothing else; expiry 90 days, with a calendar
   reminder to rotate. What it allows: starting this repository's workflows
   from `main` and reading run state. It cannot push code, change workflows,
   read secrets or touch releases.
2. As root:

   ```sh
   useradd --system --home /var/lib/vulnfeed-kick --shell /usr/sbin/nologin vulnfeed-kick
   install -d -m 0755 /opt/vulnfeed-kick
   install -m 0755 ops/kick/vulnfeed-kick.sh .github/scripts/feed-health.sh /opt/vulnfeed-kick/
   install -d -m 0750 -o root -g vulnfeed-kick /etc/vulnfeed-kick
   install -m 0640 -o root -g vulnfeed-kick /dev/null /etc/vulnfeed-kick/token
   # paste the token into /etc/vulnfeed-kick/token (one line, no newline needed)
   install -m 0644 ops/kick/vulnfeed-kick.service ops/kick/vulnfeed-kick.timer /etc/systemd/system/
   systemctl daemon-reload
   systemctl enable --now vulnfeed-kick.timer
   ```

   Needs `gh` (GitHub CLI) and `jq` on the PATH.
3. Check: `systemctl start vulnfeed-kick.service; journalctl -u vulnfeed-kick -n 20`
   shows "not due" or "dispatching publish.yml", and the Actions tab shows a
   "Feed watch" run started by workflow_dispatch.

## Operate

- Pause: `systemctl stop vulnfeed-kick.timer` (the GitHub cron and the watch
  keep running).
- Rotate the token: replace the file's content; nothing restarts.
- Remove: `systemctl disable --now vulnfeed-kick.timer`, then delete the
  units, `/opt/vulnfeed-kick`, `/etc/vulnfeed-kick` and the user, and revoke
  the token on GitHub.
- Check by hand from any machine with `gh` logged in:
  `REPO=openctemio/vulnfeed-bundles bash .github/scripts/feed-health.sh check`.
