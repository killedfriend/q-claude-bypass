#!/usr/bin/env bash
# Build macOS release artifacts. Run on macOS (GitHub Actions macos-latest).
#   bash scripts/build-macos.sh [version]
set -euo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION")}"
DIST="$ROOT/dist/macos"
STAGE="$DIST/QClaudeCode-$VERSION"
ZIP="$DIST/QClaudeCode-$VERSION-macos.zip"
PKG="$DIST/QClaudeCode-$VERSION.pkg"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "build-macos.sh must run on macOS (pkgbuild/ditto are required)." >&2
  exit 1
fi
if ! command -v pkgbuild >/dev/null 2>&1; then
  echo "pkgbuild not found; install Xcode command line tools." >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$STAGE"

for f in README.md README.ru.md README.en.md README.zh-CN.md LICENSE CHANGELOG.md VERSION; do
  [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$STAGE/$f"
done

for dir in gateway desktop docs examples macos; do
  [ -d "$ROOT/$dir" ] || continue
  mkdir -p "$STAGE/$dir"
  (cd "$ROOT" && rsync -a --exclude logs --exclude '*.pfx' --exclude 'setup.log' "$dir/" "$STAGE/$dir/")
done

cp "$ROOT/macos/install.command" "$STAGE/install.command"
chmod +x "$STAGE/install.command"
find "$STAGE/macos" -type f -name '*.sh' -exec chmod +x {} \;
chmod +x "$STAGE/macos/install.command" 2>/dev/null || true

echo "creating $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

PKGROOT="$DIST/pkgroot"
PKGSCRIPTS="$DIST/pkg-scripts"
mkdir -p "$PKGROOT/usr/local/share/qclaude" "$PKGROOT/usr/local/bin" "$PKGSCRIPTS"
rsync -a "$STAGE/" "$PKGROOT/usr/local/share/qclaude/"

cat >"$PKGROOT/usr/local/bin/qclaude-setup" <<'EOF'
#!/bin/bash
exec "/usr/local/share/qclaude/macos/install.sh" "$@"
EOF
chmod +x "$PKGROOT/usr/local/bin/qclaude-setup"

cat >"$PKGSCRIPTS/postinstall" <<'EOF'
#!/bin/bash
echo "QClaude Code runtime installed. Run: qclaude-setup" > /tmp/qclaude-pkg-message
exit 0
EOF
chmod +x "$PKGSCRIPTS/postinstall"

echo "creating $PKG"
pkgbuild \
  --root "$PKGROOT" \
  --scripts "$PKGSCRIPTS" \
  --identifier "com.qclaude.code" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG"

if command -v shasum >/dev/null 2>&1; then
  (cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$PKG")" > SHA256SUMS-macos.txt)
else
  (cd "$DIST" && sha256sum "$(basename "$ZIP")" "$(basename "$PKG")" > SHA256SUMS-macos.txt)
fi

echo
echo "zip: $ZIP"
echo "pkg: $PKG"
echo "sum: $DIST/SHA256SUMS-macos.txt"
