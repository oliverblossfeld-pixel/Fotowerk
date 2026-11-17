#!/bin/zsh
set -eu
cd -- "${0:A:h}"
app="../Fotowerk.app"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -O -parse-as-library -module-cache-path "$temp/cache" *.swift -o "$app/Contents/MacOS/Fotowerk"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Fertig: ${app:A}"
