#!/bin/bash
# Turn the per-arch patched libavformat dylibs into Avformat.framework slices exactly like upstream's
# libs-arch (rename, @rpath ids/deps) + libs (lipo) + frameworks steps, then swap them into the
# official v0.6.0 xcframework bundles. Usage: assemble-avformat-wt.sh <version> <official-dl-dir>
set -euo pipefail
V="$1"; DL="$2"
SRC="${SRC:-/Volumes/SSD2TB-Samsung/Projects/libmpv-darwin-build}"
W="$SRC/build/wt-avformat"; rm -rf "$W"; mkdir -p "$W"
INT="$SRC/build/intermediate"
arch_dylib() { # <slice>: libs-arch equivalent for libavformat only
  local cm=/System/Library/Frameworks/CoreMedia.framework/CoreMedia; case "$1" in macos-*) cm=/System/Library/Frameworks/CoreMedia.framework/Versions/A/CoreMedia;; esac
  local d="$W/arch-$1"; mkdir -p "$d"
  cp "$(find "$INT/ffmpeg_$1-video-default/lib" -name 'libavformat.*.*.*.dylib' -type f)" "$d/libavformat.60.dylib"
  local f="$d/libavformat.60.dylib"
  install_name_tool -id @rpath/libavformat.60.dylib "$f" 2>/dev/null
  otool -l "$f" | grep " name " | cut -d " " -f11 | tail -n +2 | grep -E "$SRC|^lib" | while read -r dep; do
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null; done
  # Xcode 27 SDK links the Swift overlay instead of CoreMedia.framework (avformat uses no CoreMedia symbols);
  # point it back at the system framework exactly as the official v0.6.0 binary does.
  install_name_tool -change @rpath/libswiftCoreMedia.dylib "$cm" "$f" 2>/dev/null || true
  codesign --remove "$f" 2>/dev/null || true
  echo "$f"
}
mkslice() { # <os> <xcframework-slice-name> <arch-slices...>
  local os="$1" name="$2"; shift 2; local d="$W/in-$name"; mkdir -p "$d" "$W/fw-$name"
  if [ $# -gt 1 ]; then lipo -create $(for s in "$@"; do arch_dylib "$s"; done) -output "$d/libavformat.60.dylib"
  else cp "$(arch_dylib "$1")" "$d/"; fi
  (cd "$SRC" && env -i PATH="$PATH" PROJECT_DIR="$SRC" OS="$os" DEPS="$d" OUTPUT_DIR="$W/fw-$name" bash scripts/frameworks/build.sh >/dev/null)
}
mkslice ios ios-arm64 ios-arm64
mkslice iossimulator ios-arm64_x86_64-simulator iossimulator-arm64 iossimulator-amd64
mkslice macos macos-arm64_x86_64 macos-arm64 macos-amd64
mkdir -p "$SRC/build/output"
for plat in ios macos; do
  out="libmpv-xcframeworks_${V}_${plat}-universal-video-default"
  rm -rf "$W/$out"; mkdir -p "$W/$out"
  tar -xzf "$DL/libmpv-xcframeworks_v0.6.0_${plat}-universal-video-default.tar.gz" --strip-components 1 -C "$W/$out"
  for slice in "$W/$out"/Avformat.xcframework/*/; do
    sn=$(basename "$slice"); fw="$slice/Avformat.framework"
    if [ -d "$fw/Versions/A" ]; then rel=Versions/A/Avformat; else rel=Avformat; fi
    cp "$W/fw-$sn/Avformat.framework/$rel" "$fw/$rel"; echo "swapped $plat/$sn ($(lipo -archs "$fw/$rel"))"
  done
  (cd "$W" && COPYFILE_DISABLE=1 tar -czf "$SRC/build/output/$out.tar.gz" "$out")
  shasum -a 256 "$SRC/build/output/$out.tar.gz"
done
