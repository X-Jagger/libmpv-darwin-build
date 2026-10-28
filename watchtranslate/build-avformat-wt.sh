#!/bin/bash
# Rebuild only FFmpeg (with the fMP4 seek patch) and swap Avformat.framework into the official
# libmpv-darwin-build v0.6.0 xcframework bundles; every other framework stays byte-identical.
# Usage (from the fork checkout): build-avformat-wt.sh <version> <official-dl-dir>
set -euo pipefail
B=$(cd "$(dirname "$0")" && pwd)
export PATH="$B/tc/go/bin:$B/tc/venv/bin:$B/tc/nasm/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GODEBUG=tlsmlkem=0 GOPATH="$B/tc/gopath" GOCACHE="$B/tc/gocache" GOFLAGS=-modcacherw
V="$1"; DL="$2"
SRC="${SRC:-/Volumes/SSD2TB-Samsung/Projects/libmpv-darwin-build}"
cd "$SRC"
SLICES="ios-arm64 iossimulator-arm64 iossimulator-amd64 macos-arm64 macos-amd64"
for s in $SLICES; do make VERSION="$V" "build/intermediate/ffmpeg_${s}-video-default"; done
W="$SRC/build/wt-avformat"; rm -rf "$W"; mkdir -p "$W"
dylib() { find "$SRC/build/intermediate/ffmpeg_$1-video-default" -name 'libavformat.*.dylib' -type f | head -1; }
# one dylib per xcframework slice (universal = lipo of both arches), then the project's own framework step
mkslice() { # <os> <out-name> <slices...>
  local os="$1" name="$2"; shift 2; local d="$W/in-$name"; mkdir -p "$d" "$W/fw-$name"
  local first; first=$(dylib "$1")
  if [ $# -gt 1 ]; then lipo -create $(for s in "$@"; do dylib "$s"; done) -output "$d/$(basename "$first")"; else cp "$first" "$d/"; fi
  env -i PATH="$PATH" PROJECT_DIR="$SRC" OS="$os" DEPS="$d" OUTPUT_DIR="$W/fw-$name" bash "$SRC/scripts/frameworks/build.sh" >/dev/null
}
mkslice ios ios-arm64 ios-arm64
mkslice iossimulator ios-arm64_x86_64-simulator iossimulator-arm64 iossimulator-amd64
mkslice macos macos-arm64_x86_64 macos-arm64 macos-amd64
for plat in ios macos; do
  tgz="$DL/libmpv-xcframeworks_v0.6.0_${plat}-universal-video-default.tar.gz"
  out="libmpv-xcframeworks_${V}_${plat}-universal-video-default"
  rm -rf "$W/$out"; mkdir -p "$W/$out"; tar -xzf "$tgz" --strip-components 1 -C "$W/$out"
  for slice in "$W/$out"/Avformat.xcframework/*/; do
    sn=$(basename "$slice"); fw="$slice/Avformat.framework"
    if [ -d "$fw/Versions/A" ]; then dst="$fw/Versions/A/Avformat"; new="$W/fw-$sn/Avformat.framework/Versions/A/Avformat"
    else dst="$fw/Avformat"; new="$W/fw-$sn/Avformat.framework/Avformat"; fi
    cp "$new" "$dst"; echo "swapped $plat $sn"
  done
  mkdir -p build/output; (cd "$W" && tar -czf "$SRC/build/output/$out.tar.gz" "$out")
  shasum -a 256 "build/output/$out.tar.gz"
done
