# Releasing the widget

## Ship an update

```bash
git checkout main && git pull
git tag v1.2.0          # X.Y.Z, higher than the last release
git push origin v1.2.0
```

`.github/workflows/release.yml` then tests, builds against **production**
(`https://chup.online/api/v1/`), signs when the certificate secrets exist, and
publishes a GitHub Release with three files:

| File | For |
|---|---|
| `chup-widget-setup.exe` | First install on a PC |
| `chup-widget-windows.zip` | What installed widgets download to update |
| `chup-widget-windows.zip.sha256` | The checksum the updater verifies before swapping |

## What a clinic PC does

- Checks GitHub on launch and every 6 hours (release builds only; debug runs and
  CI builds never update themselves).
- A newer release puts a green dot on ⋯ and an **Update to X.Y.Z** item in the menu.
- Clicking it downloads the zip, refuses it unless the SHA-256 matches, then hands
  over to a small PowerShell script and exits. The script waits for the widget to
  close, copies the new files over the install folder and restarts it, old or new,
  so a failed copy never leaves the doctor without the widget. Its log is
  `update.log` in the `chup-widget-update-*` temp folder.
- The menu shows the installed version when there is nothing to update.

## First install

Run `chup-widget-setup.exe`. It installs per user, without admin rights, to
`%LOCALAPPDATA%\Programs\Chup Widget`, adds a Start menu entry and starts the
widget. The widget registers itself to start with Windows on sign-in; uninstalling
removes that entry. Never change the installer's `AppId`.

## Dry run

Actions tab, **Release**, **Run workflow**, enter a version. Everything is built
and attached to the run as an artifact; nothing is published and no widget sees it.

## Before the first real release

- **Code signing.** Without a certificate, SmartScreen warns on the installer and
  may flag updated exes. Add `WINDOWS_SIGN_CERT_PFX_BASE64` and
  `WINDOWS_SIGN_CERT_PASSWORD` as repository secrets; both workflows sign once
  they exist.
- **Production backend.** Releases talk to chup.online (branch `v1`). The
  `called_at` / `started_at` / `limits` fields are on `develop` only (chup.online
  `577101b68`); until they reach `v1` the widget falls back to its own timings.
