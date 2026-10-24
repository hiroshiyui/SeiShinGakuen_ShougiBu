#!/usr/bin/env python3
"""Static accessibility scanner for the Godot scenes of 清正学園将棋部.

Reads .tscn files (text format) and export_presets.cfg and reports
mechanical a11y leads:

  * interactive nodes whose custom_minimum_size short side is below the
    project floor (warn, default 72 Godot px ≈ 41 dp) or below the Material
    ideal (info, default 84 px ≈ 48 dp on a 412 dp phone)
  * font_size overrides below the body-text floor (default 26 px)
  * text drawn as a root-level overlay with no outline
  * icon-only buttons with no text / tooltip_text / accessibility_name
  * overlays anchored to the screen edge with fractional anchors
  * VIBRATE permission missing from the Android export preset

Everything reported is a lead to confirm in context, not a verdict —
containers can stretch nodes past their minimum size.

Usage:
  a11y_scan.py                 # scan scenes/ and export_presets.cfg
  a11y_scan.py scenes/Main.tscn other.tscn
  a11y_scan.py --json
  a11y_scan.py --target-px 77 --font-px 24
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]

INTERACTIVE_TYPES = {
    "Button", "TextureButton", "OptionButton", "CheckBox", "CheckButton",
    "MenuButton", "LinkButton", "SpinBox", "HSlider", "VSlider",
}
TEXT_TYPES = {"Label", "Button", "RichTextLabel", "CheckBox", "OptionButton", "LinkButton"}

NODE_RE = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")?(?: parent="([^"]*)")?(?: instance=ExtResource\("([^"]+)"\))?', re.M)
VEC2_RE = re.compile(r"Vector2\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)")


def parse_nodes(text: str):
    """Yield (name, type, parent, props: dict) for each [node ...] block."""
    matches = list(NODE_RE.finditer(text))
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end]
        props = {}
        for line in body.splitlines():
            if "=" in line and not line.startswith("["):
                k, _, v = line.partition("=")
                props[k.strip()] = v.strip()
        yield m.group(1), m.group(2) or "", m.group(3) or "", props


def get_vec2(v: str | None):
    if not v:
        return None
    m = VEC2_RE.search(v)
    return (float(m.group(1)), float(m.group(2))) if m else None


def num(v: str | None):
    try:
        return float(v) if v is not None else None
    except ValueError:
        return None


def scan_scene(path: Path, target_px: float, floor_px: float, font_px: float, findings: list):
    text = path.read_text(encoding="utf-8")
    rel = str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path)

    for name, ntype, parent, p in parse_nodes(text):
        where = f"{rel}: {parent + '/' if parent and parent != '.' else ''}{name}"
        if ntype == "" and "instance" in text[:0]:
            pass

        # 1. Touch targets
        if ntype in INTERACTIVE_TYPES:
            v = get_vec2(p.get("custom_minimum_size"))
            if v is None:
                findings.append(dict(kind="touch-target", severity="info", where=where,
                                     msg=f"{ntype} has no custom_minimum_size; size depends entirely on container/theme — confirm ≥ {target_px:.0f} px short side on device"))
            else:
                w, h = v
                # 0 on an axis means "let the container decide"; only judge axes that are set.
                judged = [d for d in (w, h) if d > 0]
                if judged and min(judged) < floor_px:
                    findings.append(dict(kind="touch-target", severity="warn", where=where,
                                         msg=f"{ntype} custom_minimum_size {w:.0f}×{h:.0f} px; short side < {floor_px:.0f} px (≈41 dp project floor). Check whether its container stretches it."))
                elif judged and min(judged) < target_px:
                    findings.append(dict(kind="touch-target", severity="info", where=where,
                                         msg=f"{ntype} custom_minimum_size {w:.0f}×{h:.0f} px; meets the {floor_px:.0f} px floor but not the {target_px:.0f} px (48 dp) ideal"))

        # 2. Font size overrides
        fs = num(p.get("theme_override_font_sizes/font_size"))
        if fs is not None and fs < font_px:
            sev = "warn" if fs < font_px - 5 else "info"
            findings.append(dict(kind="font-size", severity=sev, where=where,
                                 msg=f"font_size override {fs:.0f} px is below the {font_px:.0f} px body floor"))

        # 3. Root-level overlay text without outline
        is_root_overlay = parent == "." and ntype in TEXT_TYPES
        if is_root_overlay:
            has_outline = "theme_override_constants/outline_size" in p
            if ntype == "Label" and not has_outline:
                findings.append(dict(kind="overlay-contrast", severity="warn", where=where,
                                     msg="root-level Label over the background with no outline_size; text may vanish over the photo/wood"))
            # 5. Fractional screen-edge anchors
            at = num(p.get("anchor_top"))
            ab = num(p.get("anchor_bottom"))
            if at is not None and at == ab and 0 < at < 0.15:
                findings.append(dict(kind="cutout", severity="warn", where=where,
                                     msg=f"anchored at {at:.0%} of screen height — collides with punch-hole cameras; position relative to the board or safe-area inset"))
            if at is not None and at == ab and 0.85 < at < 1:
                findings.append(dict(kind="cutout", severity="info", where=where,
                                     msg=f"anchored at {at:.0%} of screen height — may overlap gesture-nav bar / StatusBar row"))

        # 4. Icon-only buttons
        if ntype in {"Button", "TextureButton"}:
            has_text = p.get("text", '""') not in ('""', "")
            has_name = any(k in p for k in ("tooltip_text", "accessibility_name"))
            has_icon = "icon" in p or "texture_normal" in p or ntype == "TextureButton"
            if has_icon and not has_text and not has_name:
                findings.append(dict(kind="screen-reader", severity="warn", where=where,
                                     msg="icon-only button with no text / tooltip_text / accessibility_name — TalkBack reads nothing"))


def scan_export_preset(findings: list):
    cfg = REPO / "export_presets.cfg"
    if not cfg.exists():
        return
    text = cfg.read_text(encoding="utf-8")
    if "Input.vibrate_handheld" in "".join(
        q.read_text(encoding="utf-8") for q in (REPO / "scripts").rglob("*.gd")
    ) and not re.search(r"^permissions/vibrate=true", text, re.M):
        findings.append(dict(kind="haptics", severity="warn", where="export_presets.cfg",
                             msg="scripts call Input.vibrate_handheld() but permissions/vibrate is not true — haptic feedback is silently dropped on device"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", help=".tscn files or directories (default: scenes/)")
    ap.add_argument("--target-px", type=float, default=84.0, help="touch-target ideal in Godot px; below this is info (default 84 ≈ 48 dp)")
    ap.add_argument("--floor-px", type=float, default=72.0, help="touch-target hard floor in Godot px; below this is warn (default 72 ≈ 41 dp, the size the project settled on so chrome never shrinks the board)")
    ap.add_argument("--font-px", type=float, default=26.0, help="body text floor in px (default 26, the theme default)")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--no-info", action="store_true", help="hide info-level leads")
    args = ap.parse_args()

    roots = [Path(p) for p in args.paths] or [REPO / "scenes"]
    files: list[Path] = []
    for r in roots:
        r = r if r.is_absolute() else (REPO / r)
        files.extend(sorted(r.rglob("*.tscn")) if r.is_dir() else [r])

    findings: list[dict] = []
    for f in files:
        scan_scene(f, args.target_px, args.floor_px, args.font_px, findings)
    if not args.paths:
        scan_export_preset(findings)

    if args.no_info:
        findings = [f for f in findings if f["severity"] != "info"]

    order = {"warn": 0, "info": 1}
    findings.sort(key=lambda f: (order[f["severity"]], f["kind"], f["where"]))

    if args.json:
        json.dump(findings, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        if not findings:
            print("no leads found")
        for f in findings:
            print(f"[{f['severity']}] {f['kind']:16s} {f['where']}\n    {f['msg']}")
        warns = sum(1 for f in findings if f["severity"] == "warn")
        print(f"\n{len(findings)} leads ({warns} warn) across {len(files)} scene file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
