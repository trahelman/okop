# AGENTS.md

Guidance for AI coding agents working on this repository. User documentation is in `docs/` (Russian).

## Project

Okop routes traffic on OpenWrt: domains and subnets from lists go through a proxy or VPN, the rest goes directly. It generates a [sing-box](https://sing-box.sagernet.org/) config from UCI settings, intercepts traffic with nftables + tproxy and points dnsmasq at sing-box (fake-IP DNS). It is a fork of [Podkop](https://github.com/itdoginfo/podkop); see `NOTICE` and `docs/differences.md`.

Target: OpenWrt 24.10 (opkg, `.ipk`) and 25.12 (apk, `.apk`), sing-box ≥ 1.12.4. Both packages are architecture-independent.

## Layout

| Path | What |
|---|---|
| `okop/` | Backend package. `files/usr/bin/okop` is the main script, `files/usr/lib/*.sh` the libraries, `files/etc/` init script, default UCI config and uci-defaults |
| `luci-app-okop/` | LuCI app. `htdocs/.../view/okop/*.js` are hand-written views, except `main.js` |
| `fe-app-okop/` | TypeScript sources of `luci-app-okop/.../view/okop/main.js` (diagnostics, dashboard, validators) and the translation pipeline |
| `dev/` | Local test environment: OpenWrt in Docker, fixtures, scenarios. See `dev/README.md` |
| `docs/` | User documentation |
| `Dockerfile-ipk`, `Dockerfile-apk` | Package build on the official OpenWrt SDK |

## Shell code

- Runs under **BusyBox ash** on OpenWrt, not bash. `local`, `[[ ]]`, `=~`, `$RANDOM`, `$'..'` and `echo -e` work in OpenWrt BusyBox; arrays, `declare` and here-strings (`<<<`) do not. Check anything else on the test router (`dev/okop-dev sh`) before relying on it.
- ShellCheck: library files declare `# shellcheck shell=busybox`. CI runs Differential ShellCheck (ShellCheck 0.10, severity error) on `okop/files/usr/bin`, `okop/files/usr/lib` and `install.sh`: a change must not add findings. Check locally with `koalaman/shellcheck:stable -S warning` and compare against `main`.
- Generated sing-box JSON is built with `jq` through `sing_box_cm_*` (config manager) and `sing_box_cf_*` (facade) helpers that take and return the whole config. A `fatal` inside `config=$(...)` exits only the subshell and leaves `config` empty, so handle missing values with defaults instead of relying on it.
- Run background jobs with `run_detached` and store the pid; check ownership with `okop_background_job_running` before killing. `func > /dev/null &` keeps the caller's descriptors open in ash (it saves copies in fd 10+), which hangs `okop reload` over SSH.
- `start` must work after a run that was not stopped (crash, OOM, a second start): `cleanup_previous_run` removes the leftovers.
- dnsmasq is switched by actual state (`dnsmasq_uses_sing_box`), not by flags. Restore must return the user's settings exactly; domain forwardings (`/domain/server`) stay in place while sing-box is used.
- Log with `log "message" "level"` (syslog tag `okop`); `echolog` also prints to a terminal.

## LuCI app and frontend

- Do not edit `main.js` by hand. Change `fe-app-okop/src` and rebuild: `yarn build` in `fe-app-okop` (Node 22, `corepack enable`). CI for the frontend (`yarn ci`: format, lint, tests, build) runs on pull requests touching `fe-app-okop/`.
- Other views (`okop.js`, `section.js`, `settings.js`, ...) are plain LuCI JavaScript loaded as is. Sections are a `form.GridSection`: options are `modalonly`, the table shows summary columns. Row order is significant: the first proxy/VPN section whose lists match wins.
- New UI strings must be wrapped in `_()` and translated:
  1. `yarn locales:actualize` in `fe-app-okop` regenerates `locales/calls.json`, the `.pot` and `.ru.po` and copies them to `luci-app-okop/po/`. It needs `git config user.name/email`.
  2. Fill the new `msgstr` entries in Russian in both `fe-app-okop/locales/okop.ru.po` and `luci-app-okop/po/ru/okop.po` (they must stay identical).
  3. Keep the original header of the `.po` files; the generator replaces it.
- The product name in UI and docs is `Okop`; the package, command and UCI config are `okop`. `ip.podkop.fyi` and `fakeip.podkop.fyi` are upstream service domains and stay as they are.

## Testing

Use the test environment for every behaviour change:

```
dev/okop-dev up                 # build and start: router, LAN client, WAN proxy
dev/okop-dev scenarios          # run all scenarios, must all pass
dev/okop-dev scenario <name>    # run one
dev/okop-dev check              # DNS, HTTPS and sing-box from the client
dev/okop-dev reset              # recreate the router from a clean image
```

- Sources are mounted into the router, edits apply without rebuilding. After git replaces `okop/` or `luci-app-okop/` (e.g. a branch switch), run `reset`.
- For a bug fix, first add or extend a scenario in `dev/scenarios/` that fails on the current code, then fix it. Scenarios source `dev/lib.sh` and print `PASS:`/`FAIL:` lines.
- Checks must look at outcomes the user sees: `dig` prints timeouts to stdout, so match an address; `pidof` alone does not catch a crash loop (`singbox_stable`).
- The router image runs OpenWrt's procd, netifd, dnsmasq, fw4 and LuCI (Russian by default, `dev/okop-dev i18n` recompiles the translation). The kernel is Docker Desktop's, not OpenWrt's.

## Workflow

- Work on a branch, merge into `main` with `git merge --no-ff`, push `main`.
- Commit messages: imperative subject with a type prefix (`fix:`, `feat(luci):`, `docs:`, `dev:`, `chore:`), a body explaining why.
- Update `docs/` when user-visible behaviour changes, and `docs/differences.md` when it differs from Podkop.
- Releases: an annotated tag without a `v` prefix (`0.3`) on `main` triggers `.github/workflows/build.yml`, which builds `.ipk` and `.apk` packages and publishes a GitHub release. `install.sh` installs the latest release.
