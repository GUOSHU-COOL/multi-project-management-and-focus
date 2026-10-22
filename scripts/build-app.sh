#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/Build/云上计划.app"
contents_dir="$app_dir/Contents"
iconset_dir="$project_dir/.build/AppIcon.iconset"

cd "$project_dir"
swift build -c release

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$iconset_dir"
cp ".build/release/CloudPlan" "$contents_dir/MacOS/CloudPlan"
cp "Resources/Info.plist" "$contents_dir/Info.plist"

sips -z 16 16 Assets/AppIcon.png --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 Assets/AppIcon.png --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 Assets/AppIcon.png --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 Assets/AppIcon.png --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 Assets/AppIcon.png --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 Assets/AppIcon.png --out "$iconset_dir/icon_512x512.png" >/dev/null
cp Assets/AppIcon.png "$iconset_dir/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/AppIcon.icns"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
