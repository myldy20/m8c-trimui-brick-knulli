#!/bin/sh
set -eu

REPO="myldy20/m8c-trimui-brick-knulli"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
WORK="/userdata/system/m8c-installer.$$"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM HUP

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

download() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$url" "$output" <<'PY'
import sys
import urllib.request

url, output = sys.argv[1], sys.argv[2]
request = urllib.request.Request(url, headers={"User-Agent": "m8c-trimui-brick-installer"})
with urllib.request.urlopen(request, timeout=120) as response, open(output, "wb") as target:
    while True:
        chunk = response.read(1024 * 1024)
        if not chunk:
            break
        target.write(chunk)
PY
    else
        fail "curl, wget or python3 is required."
    fi
}

[ "$(uname -m)" = "aarch64" ] || fail "This installer is intended for the ARM64 TrimUI Brick."
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the installer."

mkdir -p "$WORK"

echo "Fetching the latest m8c package for TrimUI Brick..."
download "$API_URL" "$WORK/release.json"

python3 - "$WORK/release.json" "$WORK/assets.txt" <<'PY'
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assets = release.get("assets", [])
zip_asset = None
sha_asset = None

for asset in assets:
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name.startswith("m8c-trimui-brick-knulli-") and name.endswith(".zip"):
        zip_asset = (name, url)
    elif name.startswith("m8c-trimui-brick-knulli-") and name.endswith(".zip.sha256"):
        sha_asset = (name, url)

if not zip_asset or not sha_asset:
    raise SystemExit("Latest release does not contain the expected ZIP and checksum assets.")

pathlib.Path(sys.argv[2]).write_text(
    "\n".join([zip_asset[0], zip_asset[1], sha_asset[0], sha_asset[1]]) + "\n",
    encoding="utf-8",
)
PY

ZIP_NAME="$(sed -n '1p' "$WORK/assets.txt")"
ZIP_URL="$(sed -n '2p' "$WORK/assets.txt")"
SHA_NAME="$(sed -n '3p' "$WORK/assets.txt")"
SHA_URL="$(sed -n '4p' "$WORK/assets.txt")"

download "$ZIP_URL" "$WORK/$ZIP_NAME"
download "$SHA_URL" "$WORK/$SHA_NAME"

python3 - "$WORK/$ZIP_NAME" "$WORK/$SHA_NAME" "$WORK/unpacked" <<'PY'
import hashlib
import pathlib
import shutil
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
checksum_file = pathlib.Path(sys.argv[2])
destination = pathlib.Path(sys.argv[3])
expected = checksum_file.read_text(encoding="utf-8", errors="replace").split()[0].lower()

digest = hashlib.sha256()
with archive.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
actual = digest.hexdigest().lower()

if actual != expected:
    raise SystemExit(f"SHA-256 mismatch: expected {expected}, got {actual}")

if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
with zipfile.ZipFile(archive) as package:
    package.extractall(destination)
PY

PAYLOAD_BINARY="$(find "$WORK/unpacked" -path '*/roms/ports/m8c/m8c-bin' -type f | head -n 1)"
[ -n "$PAYLOAD_BINARY" ] || fail "The latest release uses the old package format. Publish revision 2 or newer first."

PACKAGE_INSTALLER="$(find "$WORK/unpacked" -type f -name install.sh | head -n 1)"
[ -n "$PACKAGE_INSTALLER" ] || fail "install.sh was not found in the release archive."

SLEEP_MODE="${M8C_SLEEP_PATCH:-ask}"
case "$SLEEP_MODE" in
    1|yes|true|on) SLEEP_ARG="--sleep-patch" ;;
    0|no|false|off) SLEEP_ARG="--no-sleep-patch" ;;
    ask)
        SLEEP_ARG="--no-sleep-patch"
        if [ -r /dev/tty ]; then
            printf '\nAdd autosave protection before Knulli suspend? [y/N] ' >/dev/tty
            answer=""
            IFS= read -r answer </dev/tty || true
            case "$answer" in
                y|Y|yes|YES|Yes) SLEEP_ARG="--sleep-patch" ;;
            esac
        fi
        ;;
    *) fail "Unknown M8C_SLEEP_PATCH value: $SLEEP_MODE" ;;
esac

echo
chmod 755 "$PACKAGE_INSTALLER"
sh "$PACKAGE_INSTALLER" "$SLEEP_ARG"
