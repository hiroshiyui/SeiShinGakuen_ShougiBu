# ADR-0013: Ship Linux desktop builds as AppImages

## Status

Accepted. Written 2026-10-24 on the `linux-appimage` branch (as
ADR-0011, renumbered on merge); amended 2026-11-13 — see
"Amendment: x86_64 only, from 1.1.1" at the end.

## Context

The game has always run on Linux: the Rust core was developed on
`x86_64-unknown-linux-gnu` and the dev loop is a desktop Godot window.
Only Android was ever *shipped*. ADR-level distribution decisions so far
(ROADMAP §8, 2026-04-27) settled "sideload only, no Play Store" and said
nothing about desktop because nothing desktop was planned.

Reasons to ship Linux now:

- The desktop build exists for free; the only missing pieces are
  packaging and a portability story.
- Linux players expect a single file they can `chmod +x` and run.
  AppImage is the format that needs no root, no package manager and no
  distro-specific build, and Godot's own export binary is already a
  self-contained static-ish executable.
- arm64 Linux (Raspberry Pi 4/5, Asahi, Pine64, ARM Chromebooks with
  Crostini) is a real audience for a lightweight offline board game, and
  Godot 4.7 ships arm64 Linux export templates.

Constraints discovered while doing it:

- **glibc leaks into the `.so`.** Building `libshogi_core.so` on the
  Debian trixie host produced a library requiring `GLIBC_2.43`, which
  refuses to load on any distro older than mid-2026. The Godot export
  binary itself is fine (upstream templates target an old glibc).
- **AppImage tooling has no stable release.** `appimagetool` and the
  type-2 runtime are only published under moving `continuous` tags.
- **No FUSE on the build host**, and increasingly none on user machines
  (libfuse2 is no longer installed by default on recent Ubuntu).
- **The project is portrait 720×1280.** Taller than a 1080p screen.

## Decision

1. **AppImage is the only Linux format.** No Flatpak, Snap, .deb or
   tarball. One file per architecture, named
   `seishingakuen-v<X.Y.Z>-{x86_64,aarch64}.AppImage`, attached to the
   same GitHub Release and tag as the APK. Same version number, same
   release notes, same CHANGELOG entry.
2. **The shippable `.so` is built in a Debian bullseye container**
   (glibc 2.31) via `tools/build_linux_native.sh`, never on the host.
   The floor is enforced: both the native-build script and the AppImage
   packer run `objdump -T` and fail above `GLIBC_2.31`. bullseye is EOL,
   so the image pulls from `archive.debian.org`, which is frozen and
   therefore reproducible. Ubuntu 20.04 shares the 2.31 floor, so every
   mainstream distro from 2020 onward is covered.
3. **Tooling is pinned by hash, not by tag.** `tools/appimage/appimage.lock`
   records the SHA-256 of `appimagetool-x86_64.AppImage`,
   `runtime-x86_64` and `runtime-aarch64`. The build fails if a download
   no longer matches; re-pinning is a deliberate, reviewed edit.
4. **The x86_64 host builds both images.** `appimagetool` only needs to
   run on the host; the target runtime is swapped via `--runtime-file`.
   The tool itself runs with `--appimage-extract-and-run` so FUSE is not
   required to build. The current type-2 runtime also falls back to
   extraction on user machines without libfuse2, so FUSE is not required
   to run either.
5. **Desktop window override, not a desktop layout.** `project.godot`
   sets `window_width_override.linuxbsd=540` / `height 960` under the
   `linuxbsd` feature tag (432 × 960 from 1.1.2 — see below). The portrait layout is unchanged; the window
   is resizable and the existing `size_changed` refit handles it.
   Android is untouched.
6. **arm64 is verified under emulation only.** The host has a
   `qemu-aarch64` binfmt handler; the extracted AppDir's `AppRun` boots
   headless in an arm64 Debian container (Godot starts, godot-rust
   initialises from the arm64 `.so`). Real-hardware GUI testing is not
   available. Release notes must say so until it is.
7. **itch.io stays Android-only** for now. Linux files are GitHub
   Releases only. Revisit if there is demand; the itch skill's "don't
   add other platforms" rule stands until then.

## Consequences

Good:

- Two more artefacts per release at no new signing or store burden.
  Linux has no code-signing requirement; the `.sha256` sidecar is the
  integrity story.
- The portable-`.so` discipline also protects the dev desktop build
  from "works on my trixie" drift.
- The whole pipeline is one flag: `tools/build_all.sh --linux`.

Bad / accepted:

- The builder image is 1.7 GB and the first `--linux` run takes ~10
  minutes (image build + two cold cargo builds). Cached volumes make
  later runs ~3 minutes per arch.
- The AppImage *file* cannot be executed under qemu binfmt: the type-2
  magic bytes at ELF offset 8 break qemu's binfmt match
  ("Exec format error"). Unpack with `unsquashfs -o <runtime size>` and
  run `AppRun` instead. Documented in `docs/linux-build.md`.
- `scripts/tests/ai_smoke.gd` references the `Settings` autoload and no
  longer compiles under `-s`; not part of the gate, but it means there
  is no one-shot "load model + think" script. Model loading on the
  portable `.so` was verified with an ad-hoc script instead.
- Two more smoke tests in the release checklist, one of which (arm64)
  is emulated.

## Amendment: x86_64 only, from 1.1.1 (2026-11-13)

The branch sat unmerged while 1.0.10–1.1.0 shipped, and was merged for
1.1.1. Only the **x86_64** AppImage ships: arm64 has never been tested
on real hardware, and the release checklist shouldn't carry an
emulated-only artefact. Points 1 and 6 above are narrowed accordingly.

- `tools/build_all.sh --linux` builds, exports and packs x86_64 only.
  The arm64 path stays in `tools/build_linux_native.sh` and
  `tools/build_appimage.sh` (`--arch arm64`) and in the `Linux arm64`
  export preset, so it can be revived without redoing the work.
- `rust-toolchain.toml` does not list `aarch64-unknown-linux-gnu`; the
  builder container installs it itself, and host and F-Droid builds
  shouldn't download a target they never use.
- The `Linux x86_64` preset uses the same include / exclude filters as
  the Android preset.
- Not every point of the release checklist can be scripted: export
  templates ignore `-s`, so "start a game and the AI replies" in the
  AppImage is checked by hand in a window.

## Amendment: 9:20 window, from 1.1.2 (2026-11-13)

At 540×960 (9:16) the viewport is 720×1280, and the ~900 px main-menu
panel left only a strip of the title art above it; phones (about 9:20)
get a 720×1600 viewport and show the character's face and shoulders.
The `linuxbsd` override is now 432×960: same height, phone proportions,
so every screen gets the layout already tested on devices. Everything
renders at 60 % instead of 75 %, which is still comfortable at desktop
viewing distance. A compact menu for short aspect ratios was rejected:
it would also change 16:9 Android phones and tablets for a desktop-only
issue.
