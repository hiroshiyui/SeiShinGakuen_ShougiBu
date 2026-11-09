#!/usr/bin/env python3
"""Generate expression variants of the character portraits with FLUX.2.

Drives a running ComfyUI server (default http://127.0.0.1:8188) with the
same graph and parameters as the `image_flux2.json` workflow ("Image Edit
(Flux.2 Dev)": reference-latent edit, euler, guidance 4, 20 steps, or
8 steps with the turbo LoRA via --turbo). Each character's `neutral.webp`
is the reference image; only the facial expression is re-prompted. When
the lossless original render is available (see ORIGINALS, looked up in
--originals-dir) it is used as the reference instead of the lossy WebP.

Output: `<portrait_dir>/{thinking,happy,worried,victory,defeat}.webp`,
resized to the neutral portrait's exact pixel size. Existing files are
skipped unless --force. Seeds are derived from character + expression so
a run is reproducible; pass --seed-offset to reroll.

    ./tools/gen_portrait_variants.py                      # everything missing
    ./tools/gen_portrait_variants.py -c suzuki-suzu -e worried --force
    ./tools/gen_portrait_variants.py --seed-offset 1 -c terry-clark -e happy --force

Needs ImageMagick (`magick`) for the final resize + WebP encode. After a
run, let Godot write the `.import` sidecars:

    ~/.local/bin/Godot_v4.7.2-stable_linux.x86_64 --headless --import --path .
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CHAR_ROOT = REPO / "assets" / "characters"
EXPRESSIONS = ["thinking", "happy", "worried", "victory", "defeat"]
WEBP_QUALITY = 86

# Original FLUX.2 renders the shipped neutral.webp files were encoded from.
ORIGINALS = {
    "yoshida-sensei": "Flux2_00028_.png",
    "katou-sensei": "Flux2_00030_.png",
    "nakamura-alice": "Flux2_00031_.png",
    "suzuki-suzu": "Flux2_00035_.png",
    "takahashi-yuriko": "Flux2_00037_.png",
    "terry-clark": "Flux2_00039_.png",
    "itou-akira": "Flux2_00040_.png",
    "sato-ryutaro": "Flux2_00041_.png",
}

KEEP = (
    " Change only the facial expression. Keep the same person, face shape,"
    " hairstyle, hair color, accessories, clothing, pose, camera framing,"
    " illustration style, line work, coloring and pastel background exactly"
    " the same as the reference image."
)
# The reference portraits of most characters show no hands. Mentioning
# hands at all makes the model invent (often malformed) ones, so only the
# characters that already have a hand in frame get a hand instruction.
HANDS = {
    "terry-clark": " His hand stays exactly as in the reference image, with five fingers.",
    "itou-akira": " His hands and the keyboard stay exactly as in the reference image.",
    "yoshida-sensei": " Her hand and the clipboard stay exactly as in the reference image.",
}
NO_HANDS = " Head and shoulders only: no hands, arms or fingers appear in the picture."

IDENTITY = (
    " This must clearly be the same individual as in the reference image,"
    " with the same apparent age, face proportions, eye shape and eye size,"
    " nose, mouth size, lips and skin tone. The change of expression is"
    " subtle to moderate, natural and believable, never exaggerated or"
    " cartoonish."
)
# Same, for prompts that deliberately add a hand gesture.
KEEP_FACE = (
    " Keep the same person, face shape, hairstyle, hair color, accessories,"
    " clothing, camera framing, illustration style, line work, coloring and"
    " pastel background exactly the same as the reference image."
)
POSE_CHANGES = {("katou-sensei", "thinking")}
# Rerolls that were needed to get an acceptable render; added to the
# derived seed so a full regeneration reproduces the accepted images.
SEED_OFFSETS: dict[tuple[str, str], int] = {
    ("nakamura-alice", "happy"): 1,
}

# Who each character is, from the `introduction` in their profile .tres.
# Prepended to every prompt so the expression is played in character.
PERSONA = {
    "sato-ryutaro": "He is a bright, honest, innocent elementary-school boy who loves shogi.",
    "suzuki-suzu": "She is a cheerful, sunny, friendly high-school girl, the mood-maker of her club.",
    "takahashi-yuriko": "She is a graceful, modest, well-mannered girl raised in a traditional kimono shop; her expressions are gentle and refined.",
    "itou-akira": "He is a mild-mannered, intelligent, slightly nerdy senior student who loves computers.",
    "nakamura-alice": "She is a calm, composed, cool girl who keeps a poker face and never lets her feelings show; her expressions are always very subtle.",
    "terry-clark": "He is a cool, aloof, serious and proud young man, the strongest player in the club; his expressions are restrained.",
    "yoshida-sensei": "She is a gentle, soft-spoken young teacher with a quiet touch of melancholy; her expressions are tender and understated.",
    "katou-sensei": "She is a warm, dignified, mature woman, a former professional shogi player with the calm confidence of a master.",
}

# Per-character wording, matched to each personality. The in-game avatar
# is tiny (64 px), so the expressions lean a little pronounced.
PROMPTS: dict[str, dict[str, str]] = {
    "sato-ryutaro": {
        "thinking": "The boy is thinking hard about his next move: his mouth is closed and pursed to one side, his eyebrows are furrowed, and his eyes look up and to the side.",
        "happy": "The boy beams with joy: his eyes are squeezed shut into happy curves and he has a huge open-mouthed grin, with rosy cheeks.",
        "worried": "The boy looks anxious and in trouble: his eyebrows are raised and slanted, his eyes are a little wide, and his closed mouth is a small wobbly frown.",
        "victory": "The boy cheers in triumph: his eyes are wide open and sparkling, his eyebrows are raised high, and he has a big, delighted open-mouthed smile.",
        "defeat": "The boy has just lost and is about to cry: his eyes are glossy with tears welling up, his eyebrows droop, and his lower lip is pushed out in a trembling pout.",
    },
    "suzuki-suzu": {
        "thinking": "The girl is pondering her next move: her mouth is closed and pouted slightly to one side, one eyebrow is raised, and her eyes look up and to the side behind her glasses.",
        "happy": "The girl laughs happily: her eyes are closed into cheerful crescents behind her glasses and she has a big open-mouthed laugh.",
        "worried": "The girl looks a little nervous and flustered: her eyebrows are slanted upward in worry, her eyes glance to the side behind her glasses, and her closed mouth is a tight, awkward wavy line.",
        "victory": "The girl celebrates a win: she winks one eye playfully and gives a bright, confident smile.",
        "defeat": "The girl has just lost and takes it good-naturedly: her eyes are closed, her eyebrows droop, and she has a sheepish, embarrassed crooked smile.",
    },
    "takahashi-yuriko": {
        "thinking": "The girl is concentrating quietly: her eyes are lowered and half closed, her lips are closed without a smile, and her expression is calm and serious.",
        "happy": "The girl smiles with gentle joy: her eyes are closed into soft curves and she has a warm closed-mouth smile with a light blush.",
        "worried": "The girl looks troubled: her eyebrows are drawn together and raised, her eyes are uneasy, and her lips are slightly parted in concern.",
        "victory": "The girl is modestly delighted to have won: her eyes are bright, her cheeks are lightly flushed, and she has a graceful closed-mouth smile.",
        "defeat": "The girl has just lost and accepts it gracefully: her eyes are closed, her eyebrows droop slightly, and she has a small, sad, resigned smile.",
    },
    "itou-akira": {
        "thinking": "The boy is calculating variations: his eyes are narrowed and look sharply to the side behind his glasses, his eyebrows are lowered, and his mouth is a straight focused line.",
        "happy": "The boy is pleased: he has a relaxed, friendly open smile and bright eyes behind his glasses.",
        "worried": "The boy realises he has miscalculated: his eyebrows are raised and slanted in worry, his eyes are slightly widened behind his glasses, and his closed mouth is pressed into a tense, uneasy line.",
        "victory": "The boy is proud of his win: he has a confident, pleased smile, his eyebrows are slightly raised, and his eyes shine behind his glasses.",
        "defeat": "The boy has just lost and is dejected: his eyes are downcast and half closed behind his glasses, his eyebrows droop, and his mouth is slightly open in a sigh.",
    },
    "nakamura-alice": {
        "thinking": "The girl is quietly thinking: her face stays serene and almost expressionless, with smooth relaxed eyebrows, her eyes looking down and slightly to the side, and her lips gently closed.",
        "happy": "The girl looks quietly content. Her mouth is unchanged from the reference image: the same small, narrow, closed mouth, with only the very corners of her lips lifted by a hair. The feeling shows mainly in her eyes, which are open, soft and warm, with a faint blush on her cheeks. Her eyebrows are smooth and relaxed.",
        "worried": "The girl shows only a subtle hint of unease: her face stays serene, the inner ends of her eyebrows are raised very slightly, her eyes glance to the side, and her lips are gently closed.",
        "victory": "The girl shows quiet satisfaction: her small mouth stays closed and keeps exactly the same small size and width as in the reference image, with a slight, serene upward curve of the lips. Her open, calm eyes look at the viewer, and her eyebrows are smooth and relaxed.",
        "defeat": "The girl accepts her loss serenely: her eyes are gently closed, her eyebrows are smooth and relaxed, and her closed mouth is neutral and peaceful.",
    },
    "terry-clark": {
        "thinking": "The stern boy is in deep concentration: his eyes are closed and his eyebrows are drawn together, with his mouth closed.",
        "happy": "The cool boy is quietly satisfied: his usual stern look softens, with relaxed eyebrows, calm eyes and a slight, genuine closed-mouth smile.",
        "worried": "The cool boy lets a flicker of surprise show at an unexpected move: his eyes are slightly widened, his eyebrows are tense, and his lips are pressed firmly together.",
        "victory": "The cool boy has won: he has a faint, confident closed-mouth smile with one corner of his mouth slightly raised, and steady, self-assured eyes.",
        "defeat": "The stern boy has just lost and respects his opponent: his eyes are closed, his eyebrows are relaxed, and he has a faint, bitter smile.",
    },
    "yoshida-sensei": {
        "thinking": "The woman is considering her move: her eyes glance up and to the side, her lips are slightly pursed, and her expression is thoughtful.",
        "happy": "The woman smiles warmly: her eyes are gently narrowed with tenderness and she has a soft closed-mouth smile.",
        "worried": "The woman looks quietly anxious: her eyebrows are knit slightly upward, her eyes are uneasy and look a little to the side, and her lips are pressed together.",
        "victory": "The woman is gently pleased and relieved to have won: she has a soft, modest smile with her lips barely parted, and tender, slightly narrowed eyes.",
        "defeat": "The woman has just lost and is wistful: her eyes are downcast and half closed, her eyebrows droop, and she has a small melancholy smile.",
    },
    "katou-sensei": {
        "thinking": "The woman is lost in thought, resting her chin on one hand: one hand is raised into the frame with her chin resting lightly on it. She is not smiling, her mouth is a straight closed line, and her eyes are narrowed and sharp behind her glasses, looking slightly to the side. No other objects in the picture.",
        "happy": "The woman smiles broadly and warmly, a little more than in the reference image: her lips are slightly parted in a soft laugh and her eyes are narrowed into gentle crescents behind her glasses.",
        "worried": "The woman is mildly surprised by a strong move: her eyebrows are slightly raised, her eyes are a little widened behind her glasses, and her lips are slightly parted. The expression is restrained and dignified.",
        "victory": "The woman has won with ease: she has a composed, confident closed-mouth smile with one eyebrow raised and a knowing look behind her glasses.",
        "defeat": "The woman has just lost to her student and is proud of them: her eyes are closed, her eyebrows are relaxed, and she has a gentle, contented smile.",
    },
}


def build_graph(image: str, prompt: str, seed: int, turbo: bool, prefix: str) -> dict:
    """API-format equivalent of image_flux2.json (node ids kept the same)."""
    return {
        "46": {"class_type": "LoadImage", "inputs": {"image": image}},
        "45": {"class_type": "ImageScaleToTotalPixels", "inputs": {
            "image": ["46", 0], "upscale_method": "lanczos",
            "megapixels": 1.0, "resolution_steps": 1}},
        "12": {"class_type": "UNETLoader", "inputs": {
            "unet_name": "flux2_dev_fp8mixed.safetensors", "weight_dtype": "default"}},
        "89": {"class_type": "LoraLoaderModelOnly", "inputs": {
            "model": ["12", 0], "lora_name": "Flux_2-Turbo-LoRA_comfyui.safetensors",
            "strength_model": 1.0}},
        "94": {"class_type": "PrimitiveBoolean", "inputs": {"value": turbo}},
        "92": {"class_type": "ComfySwitchNode", "inputs": {
            "switch": ["94", 0], "on_false": ["12", 0], "on_true": ["89", 0]}},
        "90": {"class_type": "PrimitiveInt", "inputs": {"value": 8}},
        "91": {"class_type": "PrimitiveInt", "inputs": {"value": 20}},
        "93": {"class_type": "ComfySwitchNode", "inputs": {
            "switch": ["94", 0], "on_false": ["91", 0], "on_true": ["90", 0]}},
        "38": {"class_type": "CLIPLoader", "inputs": {
            "clip_name": "mistral_3_small_flux2_bf16.safetensors",
            "type": "flux2", "device": "default"}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["38", 0], "text": prompt}},
        "26": {"class_type": "FluxGuidance", "inputs": {
            "conditioning": ["6", 0], "guidance": 4.0}},
        "10": {"class_type": "VAELoader", "inputs": {
            "vae_name": "full_encoder_small_decoder.safetensors"}},
        "44": {"class_type": "VAEEncode", "inputs": {"pixels": ["45", 0], "vae": ["10", 0]}},
        "43": {"class_type": "ReferenceLatent", "inputs": {
            "conditioning": ["26", 0], "latent": ["44", 0]}},
        "22": {"class_type": "BasicGuider", "inputs": {
            "model": ["92", 0], "conditioning": ["43", 0]}},
        "72": {"class_type": "GetImageSize", "inputs": {"image": ["45", 0]}},
        "48": {"class_type": "Flux2Scheduler", "inputs": {
            "steps": ["93", 0], "width": ["72", 0], "height": ["72", 1]}},
        "47": {"class_type": "EmptyFlux2LatentImage", "inputs": {
            "width": ["72", 0], "height": ["72", 1], "batch_size": 1}},
        "16": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "25": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "13": {"class_type": "SamplerCustomAdvanced", "inputs": {
            "noise": ["25", 0], "guider": ["22", 0], "sampler": ["16", 0],
            "sigmas": ["48", 0], "latent_image": ["47", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["13", 0], "vae": ["10", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {
            "images": ["8", 0], "filename_prefix": prefix}},
    }


def full_prompt(cid: str, expr: str) -> str:
    lead = PERSONA[cid] + " "
    if (cid, expr) in POSE_CHANGES:
        return lead + PROMPTS[cid][expr] + KEEP_FACE + IDENTITY
    return lead + PROMPTS[cid][expr] + KEEP + IDENTITY + HANDS.get(cid, NO_HANDS)


class Comfy:
    def __init__(self, base: str):
        self.base = base.rstrip("/")

    def _json(self, path: str, payload: dict | None = None) -> dict:
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(self.base + path, data=data,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{path}: HTTP {e.code}: {e.read().decode(errors='replace')}")

    def upload(self, path: Path, name: str, subfolder: str) -> str:
        boundary = uuid.uuid4().hex
        parts = []
        for key, val in (("subfolder", subfolder), ("overwrite", "true"), ("type", "input")):
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"'
                         f"\r\n\r\n{val}\r\n".encode())
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; '
                     f'filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()
                     + path.read_bytes() + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())
        req = urllib.request.Request(
            self.base + "/upload/image", data=b"".join(parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        with urllib.request.urlopen(req, timeout=60) as r:
            res = json.load(r)
        return f"{res['subfolder']}/{res['name']}" if res.get("subfolder") else res["name"]

    def run(self, graph: dict) -> bytes:
        pid = self._json("/prompt", {"prompt": graph})["prompt_id"]
        while True:
            time.sleep(3)
            entry = self._json(f"/history/{pid}").get(pid)
            if not entry:
                continue
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI error: {json.dumps(status.get('messages'))[:2000]}")
            images = [i for o in entry.get("outputs", {}).values() for i in o.get("images", [])]
            if images:
                q = urllib.parse.urlencode({k: images[0][k] for k in ("filename", "subfolder", "type")})
                with urllib.request.urlopen(f"{self.base}/view?{q}", timeout=60) as r:
                    return r.read()
            if status.get("completed"):
                raise RuntimeError("ComfyUI finished without an output image")


def image_size(path: Path) -> str:
    out = subprocess.run(["magick", "identify", "-format", "%wx%h", str(path)],
                         check=True, capture_output=True, text=True)
    return out.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-c", "--character", action="append", choices=sorted(PROMPTS),
                    help="character id (repeatable; default: all)")
    ap.add_argument("-e", "--expression", action="append", choices=EXPRESSIONS,
                    help="expression (repeatable; default: all)")
    ap.add_argument("--force", action="store_true", help="overwrite existing variants")
    ap.add_argument("--turbo", action="store_true", help="8-step turbo LoRA instead of 20 steps")
    ap.add_argument("--seed-offset", type=int, default=0, help="reroll with a different seed")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--originals-dir", type=Path, default=Path.home() / "Pictures" / "samples",
                    help="where the lossless original renders live (optional)")
    ap.add_argument("--out-dir", type=Path,
                    help="write <id>_<expr>.webp here instead of the portrait dirs (for trials)")
    args = ap.parse_args()

    comfy = Comfy(args.server)
    dirs = {p.name: p for p in CHAR_ROOT.glob("*/*") if (p / "neutral.webp").is_file()}
    jobs = []
    for cid in args.character or sorted(PROMPTS):
        if cid not in dirs:
            print(f"!! no neutral.webp for {cid}", file=sys.stderr)
            return 1
        for expr in args.expression or EXPRESSIONS:
            dst = (args.out_dir / f"{cid}_{expr}.webp") if args.out_dir else dirs[cid] / f"{expr}.webp"
            if dst.exists() and not args.force:
                continue
            jobs.append((cid, expr, dst))

    print(f"{len(jobs)} portrait(s) to generate")
    uploaded: dict[str, str] = {}
    for n, (cid, expr, dst) in enumerate(jobs, 1):
        src = dirs[cid] / "neutral.webp"
        if cid not in uploaded:
            ref = args.originals_dir / ORIGINALS[cid]
            if not ref.is_file():
                ref = src
            print(f"    reference for {cid}: {ref}")
            uploaded[cid] = comfy.upload(ref, cid + ref.suffix, "shougibu")
        seed = zlib.crc32(f"{cid}/{expr}".encode()) + SEED_OFFSETS.get((cid, expr), 0) + args.seed_offset
        graph = build_graph(uploaded[cid], full_prompt(cid, expr), seed,
                            args.turbo, f"shougibu/{cid}_{expr}")
        t0 = time.time()
        png = comfy.run(graph)
        dst.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            tmp.write(png)
            tmp.flush()
            subprocess.run(["magick", tmp.name, "-filter", "Lanczos",
                            "-resize", image_size(src) + "!", "-quality", str(WEBP_QUALITY),
                            str(dst)], check=True)
        print(f"[{n}/{len(jobs)}] {dst.relative_to(REPO) if dst.is_relative_to(REPO) else dst}"
              f"  ({time.time() - t0:.0f}s)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
