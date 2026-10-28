# WatchTranslate build of libmpv-darwin-build v0.6.0 (`v0.6.0-wt1`)

Purpose: fix fMP4 HLS (EXT-X-MAP) seeking in the FFmpeg 6.0 that media_kit 1.1.4 ships on iOS/macOS.
After hls.c resets the input position to 0, FFmpeg 6.0's mov demuxer keeps stale fragment/index state
(FFmpeg trac #7359): any seek or non-zero start yields `partial file` / corrupt NAL units and no audio.

What differs from upstream `v0.6.0`:
- `patches/ffmpeg-fix-fmp4-hls-seek-reset.patch`: upstream FFmpeg 380a518c rebased to 6.0 (changed lines identical),
  applied last in `scripts/ffmpeg/build.sh`.
- Release bundles: **only `Avformat.framework` is rebuilt**; the other 17 frameworks are byte-identical to the
  official `v0.6.0` release assets (`ios-universal-video-default`, `macos-universal-video-default`).
- Built locally with Xcode 27.1 (upstream CI runner macos-13 is gone). Toolchain-only tweaks in `cross-files/`:
  `-Wno-error=` for int-conversion / incompatible-function-pointer-types / implicit-function-declaration / implicit-int
  (warnings under the 2023 toolchain), and iossimulator slices use `-mios-simulator-version-min` (same version numbers)
  so the platform is IOSSIMULATOR directly instead of the upstream post-link vtool fix. New clang raises the
  arm64-simulator minos to 14.0.
- Xcode 27's SDK links `@rpath/libswiftCoreMedia.dylib` instead of `CoreMedia.framework`; libavformat uses no
  CoreMedia symbols, so the load command is pointed back at the system CoreMedia path exactly as in the official binary.
  Exported symbols per arch and the dependency list match the official Avformat binaries.
- `.github/` is left as on `main` (token has no workflow scope); CI is not used for this build.

Reproduce (toolchain: Go, meson 1.2.3, ninja, cmake, nasm on PATH; Go >= 1.24 on macOS 27 needs `GODEBUG=tlsmlkem=0`
if ffmpeg.org TLS is slow):
```sh
watchtranslate/build-avformat-wt.sh v0.6.0-wt1 <dir with the two official v0.6.0 xcframework tarballs>   # builds ffmpeg x5
watchtranslate/assemble-avformat-wt.sh v0.6.0-wt1 <same dir>    # -> build/output/libmpv-xcframeworks_v0.6.0-wt1_*.tar.gz
```
(`build-avformat-wt.sh` also contains an older inline assembly step; `assemble-avformat-wt.sh` is the authoritative one.)
