# coolguy565 pacman repository

A custom Arch Linux package repository hosted on GitHub Pages, built automatically via GitHub Actions.

## Repository Structure

```
packages/<pkgname>/PKGBUILD   # one directory per package (all are built)
build.sh                      # builds packages, signs them, runs repo-add
.github/workflows/build.yml   # CI: build + deploy to GitHub Pages + Release
cool-install                  # Arch Linux installer (archinstall-based)
quick-install                 # bootstrap script for the installer
README.md                     # this file
```

## One-time Setup

1. **Repository**: `coolguy565/coolguy565.github.io` (public). GitHub Pages serves the `gh-pages` branch.

2. **GPG Signing Key**: A dedicated GPG key is used for package signing.
   Set these repository secrets (Settings → Secrets and variables → Actions):

   | Secret            | Value                                                      |
   |-------------------|------------------------------------------------------------|
   | `GPG_KEY_B64`     | `gpg --export-secret-keys --armor KEYID \| base64 -w0`     |
   | `GPG_PASSPHRASE`  | your key's passphrase                                      |
   | `GPGKEY`          | key fingerprint (e.g., `E36138CC5F015492A1D620581C4F28ACC1A18345`) |
   | `PACKAGER_NAME`   | your key's UID name                                        |
   | `PACKAGER_EMAIL`  | your key's UID email                                       |

3. **Trigger a build**: push a commit or use **Run workflow** (Actions → build). It deploys to the `gh-pages` branch and creates a GitHub Release.

## Adding a Package

Copy a directory into `packages/`:

```
packages/hello-pacman/PKGBUILD
packages/hello-pacman/hello.sh
```

Push to main, wait for the build, done.

### PKGBUILD Guidelines

- Use `sha256sums` (not `md5sums`)
- Include `validpgpkeys` for upstream signature verification when possible
- Set `options=(!strip)` for binary packages
- Use `conflicts`/`provides` for -bin packages
- Keep packages under 100 MB (GitHub Pages limit)

## Using the Repository on Arch Linux

### 1. Add to `/etc/pacman.conf`

```
[coolguy565]
SigLevel = Required DatabaseOptional
Server = https://github.com/coolguy565/coolguy565.github.io/releases/download/coolguy565
```

### 2. Import and Trust the Signing Key

```sh
sudo pacman-key --init
curl -L -o coolguy565.asc https://github.com/coolguy565/coolguy565.github.io/releases/download/coolguy565/coolguy565.asc
sudo pacman-key --add coolguy565.asc
sudo pacman-key --lsign-key E36138CC5F015492A1D620581C4F28ACC1A18345
```

### 3. Sync and Install

```sh
sudo pacman -Sy
sudo pacman -S hello-pacman
```

## Cool Arch Installer

A full-featured Arch Linux installer with:
- Interactive TUI with sensible defaults
- Btrfs + snapshots (compress=zstd)
- Optional alongside-existing-OS install (ext4 shrink)
- Hyprland + Waybar + Walker + SDDM
- Secure Boot + TPM2 support (UEFI)
- WSL detection and support
- GitHub Pages HTTP/2 workaround (XferCommand)

### Quick Install

```bash
curl -fsSL https://coolguy565.github.io/quick-install | bash
```

This will:
1. Add the coolguy565 repo
2. Install critical packages (glibc, python, archinstall-cool)
3. Download and run the full installer

### Manual Install

```bash
# From Arch ISO as root
curl -fsSL https://coolguy565.github.io/cool-install -o cool-install
chmod +x cool-install
./cool-install
```

## GitHub Actions Workflow

The workflow (`.github/workflows/build.yml`) runs on:
- Push to `main` (changes to `packages/**`, `build.sh`, or workflow)
- Manual dispatch
- Weekly schedule (Sundays 06:00 UTC)

### Features

- **Incremental builds**: Only rebuilds packages whose sources changed (fingerprint-based)
- **Caching**: Pacman package cache + GPG home cache
- **Multi-arch**: QEMU setup for arm64 (optional)
- **Artifacts**: Build manifest uploaded for debugging
- **Deploy**: GitHub Release + GitHub Pages (gh-pages branch)
- **Lint**: Shellcheck + namcap on PKGBUILDs

### Environment Variables

| Variable | Description |
|----------|-------------|
| `REPO_NAME` | Repository name (default: coolguy565) |
| `SIGN_PACKAGES` | Enable GPG signing (default: true) |
| `GPG_KEY_B64` | Base64-encoded secret GPG key |
| `GPG_PASSPHRASE` | GPG key passphrase |
| `GPGKEY` | Key fingerprint |
| `PACKAGER_NAME` | Packager name for makepkg |
| `PACKAGER_EMAIL` | Packager email for makepkg |

## Build Script (`build.sh`)

### Features

- Incremental builds via SHA256 fingerprint of package sources
- Optional GPG signing (controlled by `SIGN_PACKAGES` and `GPG_KEY_B64`)
- Stale package cleanup (keeps only latest version per package)
- Repository database creation with `repo-add`
- Public key export for pacman verification
- Build summary with success/skip/fail counts

### Usage

```bash
# With signing (requires secrets)
GPG_KEY_B64=... GPG_PASSPHRASE=... GPGKEY=... PACKAGER_NAME=... PACKAGER_EMAIL=... ./build.sh

# Without signing (local testing)
SIGN_PACKAGES=false ./build.sh
```

## Available Packages

See `packages/` directory. Notable packages:

| Package | Description |
|---------|-------------|
| `archinstall-cool` | Trimmed archinstall for the Cool Arch installer |
| `cool-install-scripts` | Installer configs (Hyprland, Waybar, Walker, SDDM theme) |
| `linux-cool` | Custom kernel with NTFSPlus built-in (built locally) |
| `walker` | Wayland application runner |
| `vencord` | Discord client mod |
| `vesktop-bin` | Electron-based Discord with Vencord |
| `zen-browser-bin` | Firefox-based browser |
| `librewolf-bin` | Privacy-focused Firefox fork |
| `brave-bin` | Brave browser |
| `google-chrome` | Google Chrome |
| `1password` | 1Password password manager |
| `spotify` | Spotify client |
| `discord` / `discord-canary` / `discord-ptb` | Discord clients |
| `visual-studio-code-bin` | VS Code |
| `yay` | AUR helper |
| `balena-etcher-bin` | USB/SD flasher |
| `localsend-bin` | Cross-platform AirDrop alternative |
| `betterdiscord-installer` | BetterDiscord installer |

## Notes / Troubleshooting

- **Package size limit**: GitHub Pages has a 100 MB per-file limit.
- **SigLevel**: `Required DatabaseOptional` verifies every package; database signature checked when present but not required.
- **Force orphan**: Each successful build overwrites the `gh-pages` branch (`force_orphan`), so latest packages are always served.
- **Build failures**: Check Actions run log — `::error::` lines from `build.sh` indicate the cause (usually missing secret or bad PKGBUILD).
- **WSL**: The installer detects WSL and offers appropriate disk defaults.
- **HTTP/2 issue**: The repo uses `XferCommand = /usr/bin/curl --http1.1` to avoid GitHub's HTTP/2 curl error 63.

## License

MIT License - see individual packages for their licenses.