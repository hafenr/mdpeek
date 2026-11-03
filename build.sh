#!/bin/bash
# Builds build/Ogle.app. Requires the Swift toolchain, npm and curl.
set -euo pipefail
cd "$(dirname "$0")"

# The Neovim bundled for the editor pane: an official release, downloaded once.
nvim_version=v0.12.6
nvim_sha256=1dbd148222b051ba6c307c4d17a318ed083df018a4f6a5a0ce46955ffc9ab87b
nvim="build/nvim-$nvim_version"
if [[ ! -d "$nvim" ]]; then
  mkdir -p build
  curl -fsSL "https://github.com/neovim/neovim/releases/download/$nvim_version/nvim-macos-arm64.tar.gz" -o build/nvim.tar.gz
  echo "$nvim_sha256  build/nvim.tar.gz" | shasum -a 256 -c --quiet -
  rm -rf "$nvim.partial"
  mkdir "$nvim.partial"
  tar -xzf build/nvim.tar.gz -C "$nvim.partial" --strip-components 1
  rm build/nvim.tar.gz
  mv "$nvim.partial" "$nvim"
fi

# VERSION for a release; otherwise the latest tag plus the commits since it (v0.3.2 and 5 more
# commits make 0.3.2.5), so the updater sees a build of main as newer than the release it
# follows and older than the next one.
if [[ -z "${VERSION:-}" ]]; then
  IFS=- read -r tag commits _ <<<"$(git describe --tags --match 'v*' --long)"
  VERSION="${tag#v}.$commits"
fi

npm ci --no-audit --no-fund --loglevel=error
swift build -c release
bin=$(swift build -c release --show-bin-path)

app=build/Ogle.app
web="$app/Contents/Resources/web"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$web/vendor"
cp "$bin/Ogle" "$app/Contents/MacOS/"
cp -R "$bin/Sparkle.framework" "$app/Contents/Frameworks/"
cp Resources/Info.plist "$app/Contents/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/ogle.lua "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/neovim/share"
cp -R "$nvim/bin" "$nvim/lib" "$app/Contents/Resources/neovim/"
cp -R "$nvim/share/nvim" "$app/Contents/Resources/neovim/share/"
cp Resources/web/* "$web/"
cp node_modules/mermaid/dist/mermaid.min.js \
   node_modules/dompurify/dist/purify.min.js \
   node_modules/diff/dist/diff.min.js \
   node_modules/@highlightjs/cdn-assets/highlight.min.js \
   node_modules/github-markdown-css/github-markdown.css \
   "$web/vendor/"
cp node_modules/@highlightjs/cdn-assets/styles/github.min.css "$web/vendor/highlight-github.css"
cp node_modules/@highlightjs/cdn-assets/styles/github-dark.min.css "$web/vendor/highlight-github-dark.css"

# Signed ad hoc by default. With SIGN_IDENTITY set (for example "Developer ID Application"),
# signed for distribution: Neovim's parsers and binary, then Sparkle's helpers and framework,
# then the app, all with the hardened runtime and a secure timestamp. scripts/notarize.sh then
# notarizes the result.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  sign=(codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY")
  find "$app/Contents/Resources/neovim/lib" -name '*.so' -exec "${sign[@]}" {} +
  # LuaJIT compiles Lua to machine code at run time in memory it makes executable with
  # mprotect, not MAP_JIT, which the hardened runtime kills nvim for without this entitlement.
  "${sign[@]}" --entitlements Resources/nvim.entitlements "$app/Contents/Resources/neovim/bin/nvim"
  # In the order Sparkle's documentation gives, without --deep, which would drop the
  # Downloader service's own entitlements.
  "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
  "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  "${sign[@]}" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"
  "${sign[@]}" "$app"
  codesign --verify --strict --deep "$app"
else
  codesign --force --sign - "$app"
fi
echo "Built $app"
