#!/bin/bash
# Builds build/mdpeek.app. Requires the Swift toolchain and npm.
set -euo pipefail
cd "$(dirname "$0")"

npm ci --no-audit --no-fund --loglevel=error
swift build -c release

app=build/mdpeek.app
web="$app/Contents/Resources/web"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$web/vendor"
cp "$(swift build -c release --show-bin-path)/mdpeek" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp Resources/web/* "$web/"
cp node_modules/mermaid/dist/mermaid.min.js \
   node_modules/dompurify/dist/purify.min.js \
   node_modules/diff/dist/diff.min.js \
   node_modules/@highlightjs/cdn-assets/highlight.min.js \
   node_modules/github-markdown-css/github-markdown.css \
   "$web/vendor/"
cp node_modules/@highlightjs/cdn-assets/styles/github.min.css "$web/vendor/highlight-github.css"
cp node_modules/@highlightjs/cdn-assets/styles/github-dark.min.css "$web/vendor/highlight-github-dark.css"
codesign --force --sign - "$app"
echo "Built $app"
