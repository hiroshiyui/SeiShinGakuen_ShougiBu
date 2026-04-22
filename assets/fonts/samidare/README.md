# 五月雨明朝DX (XSAMIDAREMDX)

Japanese display font derived from [IPA](https://moji.or.jp/ipafont/)'s IPA
Mincho, vendored for in-game UI text (menus, dialogs, status).

- **File vendored:** `XSAMIDAREMDX.ttf` (4.7 MB)
- **Author / source:** <https://tosyokan.my.coocan.jp/tuyuzora.htm>
- **License:** IPA Font License Agreement v1.0 — see
  [`IPA_Font_License_Agreement_v1.0.txt`](./IPA_Font_License_Agreement_v1.0.txt)
  (bilingual; the Japanese text is the original binding version, the English
  translation is provided by IPA as reference).
- **License URL:** <https://moji.or.jp/ipafont/license/>

## License notes

The IPA Font License is *similar in spirit* to SIL OFL but not identical.
Practical obligations for redistributing the font inside this APK:

1. The license text must accompany the Font Software (satisfied by the
   `.txt` next to the `.ttf`).
2. A Derived Program (the app itself) may be distributed freely **so long
   as the font is redistributed under the same IPA license**; we are not
   repackaging or renaming the font, only bundling it.
3. The font may not be sold as a standalone product. Bundling inside a
   free game/app is allowed.
4. If we *modify* the font file (e.g. subsetting, renaming), the
   modified file must be clearly labelled and must also carry the IPA
   license. When we eventually run `pyftsubset` on it for APK-size
   shrinkage (see ROADMAP Phase 7), keep the original `.ttf` in the
   repo next to the subset, and preserve the license text alongside both.

The font ships unmodified from the author's 7z distribution.

## Usage

The font is not currently wired into any UI element — piece kanji on the
board still render with Fude Goshirae. To apply it to UI text (status
label, menu, dialogs), create a `Theme` resource with this font as the
default and assign it to the `Main` scene root (or to
`application/gui/theme/custom` in `project.godot` for project-wide
default). See `docs/android-gotchas.md` and the roadmap for the
string-scan-driven subsetting pattern before shipping.
