#!/bin/zsh
# Build Boxtube and install it.
#
#   scripts/install.sh            iPhone and Mac
#   scripts/install.sh iphone     just the iPhone (rerun every 7 days on a free Apple ID)
#   scripts/install.sh mac        just the Mac, into /Applications
#
# The iPhone is found automatically (first paired physical iPhone). To pick one, set
# BOXTUBE_DEVICE to its name or UDID: BOXTUBE_DEVICE=Izanagi scripts/install.sh iphone
set -euo pipefail

cd "${0:A:h}/.."
target="${1:-all}"
case "$target" in iphone|mac|all) ;; *) echo "usage: scripts/install.sh [iphone|mac|all]"; exit 2 ;; esac

say() { print -P "%F{cyan}▸%f $*"; }
fail() { print -P "%F{red}✗%f $*" >&2; exit 1; }

command -v xcodegen >/dev/null || fail "XcodeGen is missing. Install it with: brew install xcodegen"
[[ -f Config/Secrets.xcconfig ]] || print -P "%F{yellow}!%f No Config/Secrets.xcconfig: search, durations and Google sign-in will be off. See the README."

say "Generating the Xcode project"
xcodegen generate --quiet

log="build/install.log"
mkdir -p build
: > "$log"

build() { # scheme destination configuration
    xcodebuild -project Boxtube.xcodeproj -scheme Boxtube -destination "$2" -configuration "$3" \
        -derivedDataPath build -allowProvisioningUpdates -skipPackagePluginValidation build >>"$log" 2>&1 \
        || { grep -E "error:" "$log" | head -10 >&2; fail "Build failed. Full log: apple/$log"; }
}

find_iphone() {
    local json; json="$(mktemp -t boxtube-devices).json"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || fail "Couldn't list devices (is Xcode installed?)"
    /usr/bin/python3 -I - "$json" "${BOXTUBE_DEVICE:-}" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2].lower()
def usable(d):
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    return hw.get("reality") == "physical" and hw.get("deviceType") == "iPhone" \
        and conn.get("pairingState") == "paired" and conn.get("tunnelState") != "unavailable"
for d in sorted(filter(usable, devices), key=lambda d: d["connectionProperties"].get("tunnelState") != "connected"):
    name, udid = d["deviceProperties"]["name"], d["hardwareProperties"]["udid"]
    if not want or want in (name.lower(), udid.lower()):
        print(udid, name, sep="\t")
        break
PY
    rm -f "$json"
}

install_iphone() {
    local found udid name
    found="$(find_iphone)"
    [[ -n "$found" ]] || fail "No paired iPhone found. Connect it (USB or same Wi-Fi), unlock it, and trust this Mac."
    udid="${found%%$'\t'*}"; name="${found#*$'\t'}"
    say "Building for $name"
    build Boxtube "id=$udid" Debug
    say "Installing on $name"
    xcrun devicectl device install app --device "$udid" build/Build/Products/Debug-iphoneos/Boxtube.app >>"$log" 2>&1 \
        || fail "Install failed (is the phone unlocked?). Log: apple/$log"
    local expiry; expiry="$(date -v+7d '+%a %-d %b')"
    say "Boxtube is on $name. With a free Apple ID it runs until about $expiry; rerun this script before then."
}

install_mac() {
    say "Building for Mac (Release)"
    build Boxtube "platform=macOS" Release
    pkill -x Boxtube 2>/dev/null && sleep 1 || true
    rm -rf /Applications/Boxtube.app
    cp -R build/Build/Products/Release/Boxtube.app /Applications/
    codesign --verify /Applications/Boxtube.app || fail "The installed app failed its signature check"
    say "Boxtube is in /Applications"
}

[[ "$target" == mac ]] || install_iphone
[[ "$target" == iphone ]] || install_mac
