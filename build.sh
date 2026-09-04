#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_NAME="${REPO_NAME:-coolguy565}"
OUT_DIR="${OUT_DIR:-repo}"
GPG_KEY_B64="${GPG_KEY_B64:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"
GPGKEY="${GPGKEY:-}"
PACKAGER_NAME="${PACKAGER_NAME:-}"
PACKAGER_EMAIL="${PACKAGER_EMAIL:-}"
SIGN_PACKAGES="${SIGN_PACKAGES:-true}"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

if [[ -n "$GPG_KEY_B64" && "$SIGN_PACKAGES" == "true" ]]; then
  log_info "GPG signing enabled"
  export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  printf 'allow-preset-passphrase\n' > "$GNUPGHOME/gpg-agent.conf"

  echo "$GPG_KEY_B64" | base64 -d | gpg --batch --import

  gpgconf --kill gpg-agent || true
  gpgconf --launch gpg-agent

  KEYGRIP="$(gpg --with-keygrip --list-secret-keys "$GPGKEY" 2>/dev/null | awk '/Keygrip/ {print $3; exit}')"
  if [[ -z "$KEYGRIP" ]]; then
    log_error "no keygrip found for GPGKEY=$GPGKEY"
    exit 1
  fi

  GPG_PRESET="$(command -v gpg-preset-passphrase || { ls /usr/bin/gnupg/gpg-preset-passphrase 2>/dev/null || ls /usr/lib/gnupg/gpg-preset-passphrase 2>/dev/null || true; })"
  if [[ -n "$GPG_PRESET" ]]; then
    printf '%s' "$GPG_PASSPHRASE" | "$GPG_PRESET" --preset "$KEYGRIP"
  fi

  printf 'GPGKEY="%s"\nPACKAGER="%s <%s>"\n' "$GPGKEY" "$PACKAGER_NAME" "$PACKAGER_EMAIL" > "$HOME/.makepkg.conf"
else
  log_warn "GPG signing disabled (no key or SIGN_PACKAGES=false)"
  printf 'PACKAGER="%s <%s>"\n' "$PACKAGER_NAME" "$PACKAGER_EMAIL" > "$HOME/.makepkg.conf"
fi

mkdir -p "$OUT_DIR"
shopt -s nullglob

MANIFEST_FILE="$OUT_DIR/build-manifest.json"
OLD_FP_FILE="/tmp/old_fp.tsv"
FP_FILE="/tmp/fp.tsv"

fingerprint() {
  find "$1" -type f \
    -not -path '*/src/*' \
    -not -path '*/pkg/*' \
    -not -path '*/__pycache__/*' \
    -not -name '*.pkg.tar.zst' \
    -not -name '*.pkg.tar.zst.sig' \
    -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'
}

python3 - "$MANIFEST_FILE" > "$OLD_FP_FILE" <<'PY' || true
import json, sys, os
if os.path.exists(sys.argv[1]):
    for k, v in json.load(open(sys.argv[1])).items():
        print(f"{k}\t{v}")
PY
: > "$FP_FILE"

BUILD_FAILED=()
BUILD_SKIPPED=()
BUILD_SUCCESS=()

for pkgdir in packages/*/; do
  [[ -f "$pkgdir/PKGBUILD" ]] || continue
  name="${pkgdir%/}"; name="${name##*/}"
  
  if [[ -f "$pkgdir/.heavy" ]]; then
    log_info "Skipping ${name} (heavy - built locally in firejail)"
    BUILD_SKIPPED+=("$name (heavy)")
    echo -e "$name\theavy" >> "$FP_FILE"
    continue
  fi
  
  fp=$(fingerprint "$pkgdir")
  oldfp=$(awk -F'\t' -v n="$name" '$1==n{print $2}' "$OLD_FP_FILE")
  if [[ -n "$oldfp" && "$oldfp" == "$fp" ]] \
     && compgen -G "$OUT_DIR/${name}-*.pkg.tar.zst" >/dev/null; then
    log_info "Skipping ${name} (unchanged since last successful build)"
    BUILD_SKIPPED+=("$name (unchanged)")
    echo -e "$name\t$fp" >> "$FP_FILE"
    continue
  fi

  log_info "Building ${name}"
  mkg_args=(-s --noconfirm)
  [[ -f "$pkgdir/.skippgpcheck" ]] && mkg_args+=(--skippgpcheck)
  
  if ( cd "$pkgdir" && makepkg "${mkg_args[@]}" ); then
    if [[ -n "$GPG_KEY_B64" && "$SIGN_PACKAGES" == "true" ]]; then
      for pkg in "$pkgdir"/*.pkg.tar.zst; do
        [[ -f "$pkg" ]] && gpg --batch --yes --detach-sign --armor "$pkg"
      done
    fi
    BUILD_SUCCESS+=("$name")
  else
    log_error "Build failed: ${name}"
    BUILD_FAILED+=("$name")
  fi
  echo -e "$name\t$fp" >> "$FP_FILE"
  echo "::endgroup::"
done

python3 - "$MANIFEST_FILE" "$FP_FILE" <<'PY' || true
import json, sys
rows = {}
for line in open(sys.argv[2]):
    line = line.rstrip("\n")
    if not line:
        continue
    n, f = line.split("\t")
    rows[n] = f
json.dump(rows, open(sys.argv[1], "w"), indent=2)
PY

log_info "Creating repository database"
cd "$OUT_DIR"
find ../packages -maxdepth 2 -name '*.pkg.tar.zst' -exec cp {} . \;
find ../packages -maxdepth 2 -name '*.pkg.tar.zst.sig' -exec cp {} . \;

for pkgdir in ../packages/*/; do
  [[ -f "$pkgdir/PKGBUILD" ]] || continue
  pnames=$(cd "$pkgdir" && set +eu && source PKGBUILD 2>/dev/null && echo "${pkgname[@]}" || true)
  for pn in $pnames; do
    shopt -s nullglob
    matches=( ${pn}-*.pkg.tar.zst )
    shopt -u nullglob
    [[ ${#matches[@]} -gt 0 ]] || continue
    for old in $(printf '%s\n' "${matches[@]}" | sort -V | head -n -1); do
      log_info "Removing stale $old"
      rm -f "$old" "${old}.sig"
    done
  done
done

repo_add_args=(-v -R)
[[ -n "$GPG_KEY_B64" && "$SIGN_PACKAGES" == "true" ]] && repo_add_args+=(--sign)
repo-add "${repo_add_args[@]}" "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst

if [[ -n "$GPG_KEY_B64" && "$SIGN_PACKAGES" == "true" ]]; then
  gpg --export --armor "$GPGKEY" > "$REPO_NAME.asc"
else
  log_warn "Skipping GPG public key export (signing disabled)"
  : > "$REPO_NAME.asc"
fi

log_info "Build summary:"
for s in "${BUILD_SUCCESS[@]}"; do log_info "  ✓ $s"; done
for s in "${BUILD_SKIPPED[@]}"; do log_warn "  ⊘ $s"; done
for f in "${BUILD_FAILED[@]}"; do log_error "  ✗ $f"; done

if [[ ${#BUILD_FAILED[@]} -gt 0 ]]; then
  log_error "Some packages failed to build"
  exit 1
fi

log_info "Packages built and database created in ./$OUT_DIR"