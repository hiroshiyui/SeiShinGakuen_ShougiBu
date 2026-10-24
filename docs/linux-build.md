# Linux build (AppImage)

How the Linux desktop artefacts are produced, what they contain, and the
gotchas hit while setting this up. Design rationale lives in
[ADR-0011](./adr/0011-linux-appimage-secondary-target.md).

## One-liner

```bash
./tools/build_all.sh --linux --skip-apk --skip-android --skip-desktop
```

Produces:

```
build/seishingakuen-v<X.Y.Z>-x86_64.AppImage   (+ .sha256)
build/seishingakuen-v<X.Y.Z>-aarch64.AppImage  (+ .sha256)
```

`<X.Y.Z>` is `config/version` from `project.godot`.

## Pipeline

1. **Portable `.so`** — `tools/build_linux_native.sh` builds
   `libshogi_core.so` for `x86_64-unknown-linux-gnu` and
   `aarch64-unknown-linux-gnu` inside the podman image
   `seishingakuen/linux-builder:bullseye`
   (`tools/Containerfile.linux-builder`). Output lands in
   `native/bin/linux/{x86_64,arm64}/`. Each library is checked with
   `objdump -T`; any `GLIBC_` symbol above 2.31 fails the build.
2. **Godot export** — the `Linux x86_64` and `Linux arm64` presets in
   `export_presets.cfg` export a single binary with embedded PCK to
   `build/linux/<arch>/seishingakuen`. Godot copies the matching `.so`
   beside it.
3. **Headless smoke** — the x86_64 export is run with
   `--headless --quit-after 60`. Proves the PCK, the gdextension and
   the `.so` load outside the editor.
4. **AppImage** — `tools/build_appimage.sh` assembles an AppDir
   (`AppRun`, `.desktop`, icon, `usr/bin/{seishingakuen,libshogi_core.so}`)
   and runs `appimagetool`, swapping in the aarch64 runtime for the
   arm64 image.

## Prerequisites

| Need | Why |
|---|---|
| `podman` | glibc-2.31 builder container |
| Godot 4.7.2 with Linux x86_64 + arm64 export templates | export step |
| `gh` CLI | first-time download of `appimagetool` and runtimes |
| `objdump`, `unsquashfs`, `file` | glibc gate, inspection |

Tooling (`appimagetool-x86_64.AppImage`, `runtime-x86_64`,
`runtime-aarch64`) is downloaded once into `tools/.cache/appimage/`
(gitignored) from the upstream `continuous` tags and verified against
`tools/appimage/appimage.lock`. If upstream moves and a hash changes,
the build stops. To re-pin on purpose:

```bash
rm -rf tools/.cache/appimage
APPIMAGE_LOCK_UPDATE=1 ./tools/build_appimage.sh --arch all
git diff tools/appimage/appimage.lock   # review, then commit
```

No FUSE is needed: the tool runs with `--appimage-extract-and-run`, and
the current type-2 runtime falls back to extraction on user machines
without `libfuse2`.

## Verifying an AppImage

```bash
A=build/seishingakuen-v<X.Y.Z>-x86_64.AppImage
$A --headless --quit-after 60 ; echo $?           # 0, prints godot-rust init line
$A                                                 # windowed run, 540×960

# Contents and library check
off=$($A --appimage-offset)
unsquashfs -o "$off" -ll "$A" | grep usr/bin/
T=$(mktemp -d); unsquashfs -q -o "$off" -d "$T" "$A" usr/bin/libshogi_core.so
objdump -T "$T/usr/bin/libshogi_core.so" | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1   # ≤ GLIBC_2.31
```

### arm64 under emulation

The aarch64 image can be smoke-tested on an x86_64 host that has a
`qemu-aarch64` binfmt handler (`ls /proc/sys/fs/binfmt_misc/`):

```bash
A=build/seishingakuen-v<X.Y.Z>-aarch64.AppImage
RT=$(stat -c %s tools/.cache/appimage/runtime-aarch64)     # squashfs offset = runtime size
unsquashfs -q -o "$RT" -d /tmp/arm64-appdir "$A"
podman run --rm --platform linux/arm64 -v /tmp/arm64-appdir:/app:ro,Z \
  docker.io/library/debian:bookworm-slim bash -c 'cd /app && ./AppRun --headless --quit-after 60'
```

Expect the godot-rust init line and exit 0. This proves the arm64
binary and `.so` load; it does not test rendering.

## Gotchas

- **`Exec format error` running the aarch64 AppImage under binfmt.**
  AppImage type-2 files carry magic bytes `AI\x02` at ELF offset 8,
  inside the range qemu's binfmt rule masks. The kernel never hands the
  file to qemu. Unpack and run `AppRun` as above. `--appimage-offset`
  also fails on the foreign-arch file for the same reason; use the
  runtime file's size as the offset.
- **Host-built `.so` sneaks into the package.** `build_all.sh` without
  `--skip-desktop` rebuilds `native/bin/linux/x86_64/` on the host
  first; `--linux` then overwrites it with the portable build. Running
  the export step by hand after a plain `cargo build` packages a
  GLIBC_2.43 library. Both scripts' glibc gates catch this; if you see
  the error, run `tools/build_linux_native.sh` and re-export.
- **bullseye apt 404s.** bullseye is EOL; `deb.debian.org` no longer
  serves `bullseye-security`. The Containerfile points at
  `archive.debian.org` with `Check-Valid-Until` off.
- **`pkill -f` kills your shell.** When stopping a test run from a
  script, `pkill -f seishingakuen` matches the invoking shell's own
  command line. Use `pkill -x seishingakuen`.
- **Window taller than the screen.** Only if the `linuxbsd` overrides in
  `project.godot` are removed. They are what keeps the 720×1280 project
  at 540×960 on desktop.
- **Rust version drift.** `tools/Containerfile.linux-builder` reads the
  Rust version from `rust-toolchain.toml` at image-build time. After
  bumping the toolchain, run `tools/build_linux_native.sh --rebuild-image`.
