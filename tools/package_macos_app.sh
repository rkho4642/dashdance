#!/bin/zsh
# Packages the macOS build as "Dashdance.app" (ad-hoc signed). Nothing from the
# game enters the bundle: only the executable and the vendored Slippi Sys folder.
# Usage: tools/package_macos_app.sh <build-dir> <output-dir>
# APP_NAME=DashDance2 packages a side-by-side copy under its own name and bundle identifier
# (it shares Dashdance's settings, sign-in and replays in ~/Library/Application Support/Dashdance).
set -euo pipefail
ROOT="${0:A:h:h}"
BUILD="${1:?build dir}"
OUT="${2:?output dir}"
VERSION="$(head -n1 "$ROOT/VERSION")"
APP_NAME="${APP_NAME:-Dashdance}"
APP="$OUT/$APP_NAME.app"
EXE="$BUILD/port/melee_port_mac"
[[ -x "$EXE" ]] || { echo "missing $EXE; build target melee_port_mac first" >&2; exit 1; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed "s/@VERSION@/$VERSION/g" "$ROOT/port/app/macos/Info.plist" > "$APP/Contents/Info.plist"
if [[ "$APP_NAME" != "Dashdance" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" \
    -c "Set :CFBundleIdentifier app.dashdance.macos.${APP_NAME:l}" "$APP/Contents/Info.plist"
fi
cp "$EXE" "$APP/Contents/MacOS/Dashdance"
cp -R "$ROOT/port/slippi_sys" "$APP/Contents/Resources/slippi_sys"
# Replay playback: the game translated with Slippi's playback codes, a second executable the dashboard starts for
# "Watch this game". PLAYBACK_BUILD names its build directory (default: <build-dir>-playback); without it the app
# still works and says replays are not part of the build.
PLAYBACK_EXE="${PLAYBACK_BUILD:-$BUILD-playback}/port/melee_port_mac"
if [[ -x "$PLAYBACK_EXE" ]]; then
  cp "$PLAYBACK_EXE" "$APP/Contents/MacOS/DashdancePlayback"
  cp -R "$ROOT/port/slippi_sys_playback" "$APP/Contents/Resources/slippi_sys_playback"
  # The replay code list the playback build was translated with (Slippi's codes, not game data): the app compares a
  # replay's own list with it and turns resync on when they differ.
  [[ -f "$ROOT/build/playback-codes/gecko_list.bin" ]] && cp "$ROOT/build/playback-codes/gecko_list.bin" "$APP/Contents/Resources/playback_codes.bin"
  echo "playback: bundled $PLAYBACK_EXE"
else
  echo "playback: no $PLAYBACK_EXE, replays will not play in this bundle"
fi
cp "$ROOT/port/app/icons/AppIcon.icon/Assets/glyph.png" "$APP/Contents/Resources/AppMark.png"   # the hero mark in the dashboard
cp -R "$ROOT/port/app/art/controller" "$APP/Contents/Resources/controller"                        # controller editor artwork
# App icon: the Icon Composer bundle (the Dashdance mark as a glass layer over violet) compiled by
# actool into Assets.car + AppIcon.icns, so macOS 26 renders it as Liquid Glass. Older toolchains fall
# back to the flat 1024px master.
# actool lives in Xcode, not in the Command Line Tools; point at Xcode for this one step when it is installed.
# A side-by-side copy gets an orange icon so the two apps can be told apart in the Dock and Finder.
ICON_SRC="$ROOT/port/app/icons/AppIcon.icon"
if [[ "$APP_NAME" != "Dashdance" ]]; then
  ICON_SRC="$(mktemp -d)/AppIcon.icon"
  cp -R "$ROOT/port/app/icons/AppIcon.icon" "$ICON_SRC"
  sed -i '' 's/"linear-gradient": \[[^]]*\]/"linear-gradient": ["srgb:1.00000,0.62000,0.10000,1.00000", "srgb:0.80000,0.27000,0.00000,1.00000"]/' "$ICON_SRC/icon.json"
fi
ACTOOL_DEV="${DEVELOPER_DIR:-}"; [[ -z "$ACTOOL_DEV" && -d /Applications/Xcode.app/Contents/Developer ]] && ACTOOL_DEV=/Applications/Xcode.app/Contents/Developer
if [[ -n "$ACTOOL_DEV" ]] && DEVELOPER_DIR="$ACTOOL_DEV" xcrun --find actool >/dev/null 2>&1 && DEVELOPER_DIR="$ACTOOL_DEV" xcrun actool "$ICON_SRC" --compile "$APP/Contents/Resources" \
     --output-format human-readable-text --warnings --errors --output-partial-info-plist "$(mktemp)" --app-icon AppIcon \
     --include-all-app-icons --enable-on-demand-resources NO --development-region en --target-device mac \
     --minimum-deployment-target 26.0 --platform macosx >/dev/null 2>&1 && [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  echo "icon: Icon Composer bundle compiled with actool"
else
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ROOT/port/app/icons/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$ROOT/port/app/icons/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --deep "$APP"
codesign --verify --deep --strict "$APP"
echo "packaged $APP ($VERSION)"
