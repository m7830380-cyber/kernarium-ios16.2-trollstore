#!/bin/bash
set -euo pipefail
IN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
MIN=${3:-16.2}
R=$PWD/report.txt; : > "$R"
rm -rf w && mkdir w && cd w && unzip -q "$IN"
APP=$(find Payload -maxdepth 1 -type d -name '*.app' -print -quit)
[ -n "$APP" ] || { echo 'No .app bundle found' >&2; exit 1; }
# Lower every bundle minimum, including extensions and embedded frameworks.
find Payload -name Info.plist -print0 | while IFS= read -r -d '' p; do
  if /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$p" >/dev/null 2>&1; then
    old=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$p")
    echo "plist $p: $old -> $MIN" >> "$R"
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $MIN" "$p"
  fi
done
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
: > ../machos.txt
# Patch every Mach-O, preserving its linked SDK version while lowering minos.
find Payload -type f -print0 | while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  echo "$f" >> ../machos.txt
  ent=$(mktemp)
  codesign -d --entitlements :- "$f" > "$ent" 2>/dev/null || true
  [ -s "$ent" ] && cp "$ent" "$f.ent.plist.tmp"
  rm -f "$ent"
  echo "== $f: $(vtool -show-build "$f" 2>/dev/null | grep -E 'minos|sdk' | tr -s ' ' | tr '\n' ' ')" >> "$R"
  codesign --remove-signature "$f" 2>/dev/null || true
  vtool -set-build-version ios "$MIN" 27.0 -replace -output "$f.new" "$f"
  mv "$f.new" "$f"
done
[ -s ../machos.txt ] || { echo 'No Mach-O binaries found in IPA' >&2; exit 1; }
# Imports added after iOS 16.2 are weak so absent APIs do not block launch.
python3 ../weaken.py "$APP/Andarium" \
  '_$s7SwiftUI12TupleContentVyxxQp_QPGAA07ToolbarD0AARvzAaERzlMc' \
  '_$s7SwiftUI13PreferenceKeyP22_preferenceValuesEqualySb5ValueQz_AFtFZTq' \
  '_$s7SwiftUI13PreferenceKeyPAASQ5ValueRpzrlE22_preferenceValuesEqualySbAE_AEtFZ' \
  _AVAudioSessionDeactivationContextKey _AVAudioSessionResumptionContextKey >> "$R"
RB="_AVAudioSessionDidBecomeInactiveNotification=_AVAudioSessionInterruptionNotification _AVAudioSessionResumptionRecommendationNotification=_AVAudioSessionInterruptionNotification"
for f in "$APP"/Frameworks/KRuntime_*/KRuntime_*; do
  [ -f "$f" ] || continue
  python3 ../weaken.py "$f" _AVAudioSessionDeactivationContextKey _AVAudioSessionResumptionContextKey >> "$R"
  python3 ../rebind.py "$f" $RB >> "$R"
done
# Current SDK inventory is a report aid; device testing remains required.
echo "### Build SDK $(xcrun --sdk iphoneos --show-sdk-version); target iOS $MIN" >> "$R"
python3 ../symcheck.py "$SDK" ../machos.txt >> "$R" 2>&1 || true
# TrollStore accepts ad-hoc signatures; nested code is signed before the app.
tac ../machos.txt | while IFS= read -r f; do
  e="$f.ent.plist.tmp"
  if [ -f "$e" ]; then
    codesign -f -s - --entitlements "$e" "$f" >/dev/null 2>&1 || codesign -f -s - "$f"
    rm -f "$e"
  else
    codesign -f -s - "$f" >/dev/null 2>&1 || true
  fi
done
find Payload -depth \( -name '*.framework' -o -name '*.appex' \) -exec codesign -f -s - {} \; 2>/dev/null || true
codesign -f -s - --entitlements <(codesign -d --entitlements :- "$APP" 2>/dev/null || echo '<plist/>') "$APP" >/dev/null 2>&1 || true
zip -qry "$OUT" Payload
cat "$R" | head -300
