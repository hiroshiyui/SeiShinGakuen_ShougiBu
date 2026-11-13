#!/usr/bin/env python3
"""Generate the player-avatar portraits with FLUX.3 Image Klein.

Drives a running ComfyUI server (default http://127.0.0.1:8188) with the
graph of the `image_flux3_klein_image_edit` workflow template (base int8
checkpoint, euler / simple, 50 steps; --distilled switches to the distilled
checkpoint at 16 steps, cfg 1, for quick drafts). The original
lossless renders of two shipped portraits go in as style references,
`<ref_image_0>` and `<ref_image_1>`, so the avatars share the opponents'
art style, framing and pastel background while each prompt describes a
new student. Two references average the style out; with one, the new
face drifts toward that character's face. With 伊藤明 as a reference,
a boy with short dark hair came out as 伊藤明 himself, glasses included;
with two girls, the boys came out girlish. Boys therefore pair 中村アリス
with テリー・クラーク, whose curly hair, features and raised hand are
far enough from every avatar that the prompt overrides them.

Output: `assets/characters/player_avatars/<id>.webp`, 880x1168 like the opponent
portraits. Existing files are skipped unless --force. Seeds are derived
from the avatar id, so a run is reproducible; SEED_OFFSETS records the
rerolls that were picked. Avatars listed in ACCEPTED are installed from
their approved ComfyUI render instead of being rendered again.

    ./tools/gen_avatars.py                          # everything missing
    ./tools/gen_avatars.py -a girl-03 --force
    ./tools/gen_avatars.py --candidates 3 --out-dir /tmp/try   # trials

With --out-dir, each candidate is written as `<id>_s<offset>.webp` to
that directory for review instead of into the asset folder. Needs
ImageMagick (`magick`). After a run, let Godot write the `.import`
sidecars:

    ~/.local/bin/Godot_v4.7.2-stable_linux.x86_64 --headless --import --path .

then set `compress/mode=1` and `compress/lossy_quality=0.85` in each new
`.webp.import`, as the opponent portraits have, and import again: Godot's
default is lossless, which made the 16 avatars 5.7 MB in the APK instead
of 0.75 MB.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

from gen_portrait_variants import IDENTITY, KEEP, NO_HANDS, NO_OBJECTS, Comfy, encode

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "assets" / "characters" / "player_avatars"
WIDTH, HEIGHT = 880, 1168
BASE = {"unet": "flux3-image-klein-base-int8-convrot.safetensors", "steps": 50, "cfg": 3.5}
DISTILLED = {"unet": "flux3-image-klein-int8-convrot.safetensors", "steps": 16, "cfg": 1.0}

# Style references: the original FLUX.2 renders of the shipped neutral
# portraits (looked up in --originals-dir), falling back to the WebP.
_STUDENTS = REPO / "assets/characters/students"
REFERENCES = {
    "girl": [("Flux2_00031_.png", _STUDENTS / "nakamura-alice/neutral.webp"),
             ("Flux2_00040_.png", _STUDENTS / "itou-akira/neutral.webp")],
    "boy": [("Flux2_00031_.png", _STUDENTS / "nakamura-alice/neutral.webp"),
            ("Flux2_00039_.png", _STUDENTS / "terry-clark/neutral.webp")],
}

UNIFORM = ("wearing the navy blue school blazer uniform, a white shirt and a red necktie")
STYLE = (
    "Take only the drawing style from <ref_image_0> and <ref_image_1>: the same anime"
    " rendering, line work, skin shading, soft rim lighting, pastel pink-to-cream gradient"
    " background, camera distance and straight-on head-and-shoulders framing. Do not copy the"
    " people in the reference images: this is a different person, with a different face,"
    " hairstyle and hair color. The student looks straight at the viewer. No hands, no arms"
    " raised, no props, no objects, no text."
)
# Every avatar is pinned down feature by feature (face, eyes, hair, one
# accessory, glasses or not, expression) rather than by a loose
# sentence: with too little to go on, the model fills the gaps from the
# style references and the face comes out as one of the opponents.
# Each one is also kept clear of the eight opponents (中村アリス pink
# blunt bob, 鈴木すず long brown hair + glasses, 高橋百合子 black side
# ponytail, 伊藤明 short black hair + glasses, テリー curly black hair,
# 佐藤竜太郎 cap, the two teachers) and of each other: no two share a
# hair color and style, and only three wear glasses, each a different
# kind.
AVATARS: dict[str, dict[str, str]] = {
    # --- girls ---------------------------------------------------------
    "girl-01": {  # shy first-year bookworm
        "who": "a 15 years old Japanese first-year high school girl, quiet and bookish",
        "face": "a small oval face with soft cheeks",
        "eyes": "large, gentle, slightly droopy dark brown eyes",
        "hair": "glossy black hair in two neat low braids resting over her shoulders,"
                " with straight-cut bangs above her eyebrows",
        "extra": "small red hair ties at the ends of her braids",
        "mood": "a shy, gentle closed-mouth smile and a faint blush",
    },
    "girl-02": {  # second-year track athlete
        "who": "a 16 years old Japanese second-year high school girl, a sprinter on the"
               " track team",
        "face": "a heart-shaped face with lightly sun-tanned skin",
        "eyes": "bright, lively amber eyes",
        "hair": "a short dark brown pixie cut with side-swept bangs, ears showing",
        "extra": "a small white adhesive bandage on her left cheek",
        "mood": "a confident, sporty grin showing her teeth",
    },
    "girl-03": {  # cheerful first-year
        "who": "a 15 years old Japanese first-year high school girl, cheerful and energetic",
        "face": "a round face with rosy cheeks",
        "eyes": "bright emerald green eyes",
        "hair": "long chestnut brown hair in a high ponytail, with a single cowlick on top",
        "extra": "a large white ribbon tied around the base of her ponytail at the back of"
                 " her head, its loops and long tails hanging beside the ponytail, not a"
                 " bow on top of her head",
        "mood": "a bright, open-mouthed happy smile",
    },
    "girl-04": {  # third-year class representative
        "who": "a 17 years old Japanese third-year high school girl, the class representative",
        "face": "a slim oval face with a pointed chin",
        "eyes": "calm, intelligent violet-gray eyes",
        "hair": "straight black shoulder-length hair parted on the side",
        "extra": "a small silver hair clip above her right temple",
        "glasses": "thin red-framed rectangular glasses",
        "mood": "a composed expression with a faint, confident smile",
    },
    "girl-05": {  # mischievous first-year
        "who": "a 15 years old Japanese first-year high school girl, playful and mischievous",
        "face": "a small, petite, sweet face with soft cheeks",
        "eyes": "large, bright, wide-open golden-hazel eyes, only slightly upturned at the"
                " outer corners",
        "hair": "light honey-brown wavy hair in two twin tails",
        "extra": "black ribbons tying her twin tails",
        "mood": "a cheerful, cheeky closed-mouth smile, friendly and playful, never sly"
                " or menacing",
    },
    "girl-06": {  # elegant third-year
        "who": "a 17 years old Japanese third-year high school girl, elegant and mature",
        "face": "a long, graceful oval face",
        "eyes": "long-lashed, half-lidded deep blue eyes",
        "hair": "very long, straight blue-black hair in a hime cut, with blunt side locks"
                " at her cheeks",
        "extra": "a small beauty mark under her left eye",
        "mood": "a serene, elegant expression with closed lips",
    },
    "girl-07": {  # exchange student from Finland
        "who": "a 16 years old Finnish exchange student girl",
        "face": "a fair-skinned face with light freckles across her nose",
        "eyes": "pale ice-blue eyes",
        "hair": "pale platinum blonde hair, long and loose, with the top half gathered"
                " in a small knot at the back",
        "extra": "small light-blue stud earrings",
        "mood": "a calm, friendly closed-mouth smile",
    },
    "girl-08": {  # sleepy second-year
        "who": "a 16 years old Japanese second-year high school girl, sleepy and laid-back",
        "face": "a soft, slightly round face",
        "eyes": "sleepy, half-lidded gray-green eyes",
        "hair": "a messy teal chin-length bob with a cowlick sticking up",
        "extra": "a yellow star-shaped hairpin",
        "mood": "a relaxed, drowsy little smile",
    },
    # --- boys ----------------------------------------------------------
    "boy-01": {  # energetic first-year
        "who": "a 15 years old Japanese first-year high school boy, energetic and hot-blooded",
        "face": "a youthful face with a strong jaw",
        "eyes": "bright orange-brown eyes",
        "hair": "chestnut brown short spiky hair",
        "extra": "a small adhesive bandage across the bridge of his nose",
        "mood": "an energetic, confident grin",
    },
    "boy-02": {  # strict student-council third-year
        "who": "a 17 years old Japanese third-year high school boy, the strict student-council"
               " vice president",
        "face": "a long face with a sharp jaw and thin eyebrows",
        "eyes": "sharp, narrow, upturned slate-gray eyes",
        "hair": "neat dark navy-blue hair slicked back off his forehead",
        "extra": "a plain blazer lapel with no badge or pin",
        "mood": "a serious, composed expression with closed lips",
    },
    # boy-03 has amblyopia: his dark-tinted glasses are an assistive device
    # that protects his eyes, not a fashion accessory. They stay on, worn
    # normally, in every render and expression; nothing should play them
    # as a "cool" prop (pushed up, lowered, peered over or taken off).
    "boy-03": {  # talkative first-year (a buzz cut would read as a sports-club kid)
        "who": "a 15 years old Japanese first-year high school boy, cheerful and talkative",
        "face": "a round, friendly face with thick dark eyebrows",
        "eyes": "medium-sized, slightly narrow dark brown eyes that crinkle when he smiles,"
                " not large",
        "hair": "short black hair in a neat two-block cut: the sides and back clipped very"
                " short, the top a little longer and brushed forward into a short, textured"
                " fringe",
        "extra": "a natural, healthy complexion",
        "glasses": "black wayfarer-style tinted glasses with dark gray lenses, worn"
                   " normally as protective glasses for his eyes",
        "mood": "a wide, cheerful open-mouthed smile",
    },
    "boy-04": {  # laid-back third-year
        "who": "a 17 years old Japanese third-year high school boy, easygoing and laid-back",
        "face": "a slim face",
        "eyes": "relaxed, droopy hazel eyes",
        "hair": "slightly long, wavy light ash-brown hair reaching his chin",
        "extra": "a tiny silver stud earring in his left ear and a loosened necktie",
        "mood": "an easygoing half smile",
    },
    "boy-05": {  # shy first-year
        "who": "a 15 years old Japanese first-year high school boy, small and shy",
        "face": "a small, boyish face",
        "eyes": "large, round, timid dark eyes",
        "hair": "a fluffy jet-black mushroom cut with heavy bangs reaching his eyebrows",
        "extra": "a light blush on his cheeks",
        "mood": "a shy, slightly nervous smile",
    },
    "boy-06": {  # Indian-Japanese second-year
        "who": "a 16 years old Indian-Japanese second-year high school boy",
        "face": "a friendly face with warm brown skin and thick dark eyebrows",
        "eyes": "large, dark brown eyes with long lashes",
        "hair": "short, wavy black hair with a neat side part",
        "extra": "small dimples in his cheeks",
        "mood": "a warm, friendly smile showing a little of his teeth",
    },
    "boy-07": {  # cool second-year
        "who": "a 16 years old Japanese second-year high school boy, cool and aloof",
        "face": "a slender face with fine features",
        "eyes": "sharp, deep wine-red eyes",
        "hair": "dark red-brown hair with long bangs swept over his right eye",
        "extra": "his collar slightly open under the necktie",
        "mood": "a cool, quietly confident smirk",
    },
    "boy-08": {  # gentle big second-year
        "who": "a 16 years old Japanese second-year high school boy, big, broad-shouldered"
               " and gentle",
        "face": "a round, gentle face with soft cheeks",
        "eyes": "kind, narrow, smiling brown eyes",
        "hair": "soft, short brown hair with a center part, the fringe parted down the"
                " middle and falling to both sides of his forehead in two gentle curtains",
        "extra": "a broad build that fills the frame",
        "glasses": "round tortoiseshell glasses",
        "mood": "a kind, warm smile",
    },
}

# Rerolls picked during review; added to the derived seed.
SEED_OFFSETS: dict[str, int] = {"boy-03": 2, "girl-03": 1, "girl-05": 1}

# The approved render of each avatar: a lossless PNG in --accepted-dir
# (ComfyUI's output folder). Installing an accepted avatar encodes that
# PNG instead of rendering again, so the shipped image survives prompt
# edits; the exact prompt, seed and references that made it are in the
# PNG's ComfyUI metadata. These also serve as the lossless references
# for the expression variants. girl-04, girl-07 and boy-01 come from
# an earlier, shorter wording of the prompt (no face / eyes / extra
# fields) and were kept as they were. boy-02 is an --edit of a render
# made with 中村アリス + 高橋百合子 as references, with the student-council
# pin taken off his lapel (the source render is the edit's
# <ref_image_0> in its metadata). boy-08 is an --edit too: his bowl cut
# (too close to boy-05's mushroom cut) became a center-parted fringe.
# girl-03 is an --edit of her second render (seed offset 1; the first
# came out in a thick-lined cel style unlike the rest), moving a bow
# from the top of her head back to her ponytail. girl-08 is an --edit
# recoloring her dark brown hair teal, apart from girl-02's brown bob.
# boy-03 went through two edits of his third render: teeth drawn into
# his open smile (edit_00001), then sunglasses added (edit_00002).
ACCEPTED: dict[str, str] = {
    "boy-01": "avatar_boy-01_00004_.png",
    "boy-02": "avatar_boy-02_edit_00001_.png",
    "boy-03": "avatar_boy-03_edit_00002_.png",
    "boy-04": "avatar_boy-04_00001_.png",
    "boy-05": "avatar_boy-05_00001_.png",
    "boy-06": "avatar_boy-06_00001_.png",
    "boy-07": "avatar_boy-07_00001_.png",
    "boy-08": "avatar_boy-08_edit_00001_.png",
    "girl-01": "avatar_girl-01_00001_.png",
    "girl-02": "avatar_girl-02_00001_.png",
    "girl-03": "avatar_girl-03_edit_00001_.png",
    "girl-04": "avatar_girl-04_00001_.png",
    "girl-05": "avatar_girl-05_00001_.png",
    "girl-06": "avatar_girl-06_00001_.png",
    "girl-07": "avatar_girl-07_00001_.png",
    "girl-08": "avatar_girl-08_edit_00001_.png",
}


def prompt_for(aid: str) -> str:
    a = AVATARS[aid]
    he, his = ("She", "her") if aid.startswith("girl") else ("He", "his")
    glasses = (f" {he} wears {a['glasses']}." if "glasses" in a
               else f" {he} does not wear glasses.")
    extra = f" {he} has {a['extra']}." if a.get("extra") else ""
    return (
        f"Create a new anime-style illustration of {a['who']}. {he} has {a['face']},"
        f" {a['eyes']}, and {a['hair']}.{extra}{glasses} {he} is {UNIFORM}."
        f" {his.capitalize()} expression: {a['mood']}. {STYLE}"
    )


def build_graph(prompt: str, seed: int, refs: list[str], prefix: str, model: dict) -> dict:
    """API-format graph of the FLUX.3 Klein image-edit template, with the
    output latent fixed to the portrait size. The base model gets a real
    (empty) negative prompt for CFG; the distilled one runs at cfg 1, where
    the template zeroes the negative out."""
    neg = ({"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": ""}}
           if model["cfg"] > 1.0 else
           {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}})
    rin: dict = {"positive": ["4", 0], "negative": ["32", 0], "vae": ["3", 0],
                 "resolution": "resize", "resolution.megapixels": 1.0}
    g: dict = {
        "1": {"class_type": "UNETLoader", "inputs": {
            "unet_name": model["unet"], "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {
            "clip_name": "qwen3vl_4b_int8_convrot.safetensors", "type": "flux3", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "32": neg,
        "6": {"class_type": "EmptyFlux2LatentImage", "inputs": {
            "width": WIDTH, "height": HEIGHT, "batch_size": 1}},
        "17": {"class_type": "ReferenceMultiLatent", "inputs": rin},
        "7": {"class_type": "KSampler", "inputs": {
            "model": ["1", 0], "seed": seed, "steps": model["steps"], "cfg": model["cfg"],
            "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
            "positive": ["17", 0], "negative": ["17", 1], "latent_image": ["6", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": prefix}},
    }
    for i, name in enumerate(refs):
        g[f"r{i}"] = {"class_type": "LoadImage", "inputs": {"image": name}}
        rin[f"images.image{i}"] = [f"r{i}", 0]
    return g


# For a restyle (--edit-style): the content comes from <ref_image_0>,
# only the drawing style from the others.
EDIT_KEEP_RESTYLE = (
    " Keep the same person and everything about her or him from <ref_image_0>: face"
    " shape, hairstyle, hair color, accessories, eye color, expression, uniform, pose and"
    " framing. Only the drawing style changes. No hands, no props, no text."
)
EDIT_KEEP = (
    " Keep everything else in <ref_image_0> exactly the same: the same person, face,"
    " expression, eyes, hair, uniform, necktie, lighting, colors, line work, pastel"
    " background and framing."
)


def edit(args) -> int:
    """One targeted change to an already-rendered avatar, so a face that
    was liked survives a fix (e.g. removing a stray badge)."""
    if not args.avatar or len(args.avatar) != 1 or not args.edit_source:
        print("!! --edit needs exactly one -a and --edit-source", file=sys.stderr)
        return 1
    aid = args.avatar[0]
    model = dict(DISTILLED if args.distilled else BASE)
    comfy = Comfy(args.server)
    refs = [comfy.upload(args.edit_source, "avatar-edit-" + args.edit_source.name, "shougibu")]
    for style in args.edit_style or []:
        refs.append(comfy.upload(style, "avatar-style-" + style.name, "shougibu"))
    keep = EDIT_KEEP_RESTYLE if len(refs) > 1 else EDIT_KEEP
    seed = zlib.crc32(f"avatar-edit/{aid}".encode()) + args.seed_offset
    t0 = time.time()
    png = comfy.run(build_graph(args.edit.strip() + keep, seed, refs,
                                f"shougibu/avatar_{aid}_edit", model))
    out = args.out_dir or OUT_DIR
    dst = out / (f"{aid}_edit_s{args.seed_offset}.webp" if args.out_dir else f"{aid}.webp")
    dst.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
        tmp.write(png)
        tmp.flush()
        encode(Path(tmp.name), dst, f"{WIDTH}x{HEIGHT}", Path(tmp.name), None)
    print(f"edited {aid} -> {dst}  ({time.time() - t0:.0f}s)")
    return 0


# --- expression variants ----------------------------------------------
# Same five expressions as the opponents (CharacterProfile.portrait_dir),
# made by editing each avatar's ACCEPTED render with only the expression
# re-prompted, and the opponents' guard wording (KEEP, IDENTITY, NO_HANDS,
# NO_OBJECTS from gen_portrait_variants). Wording is scaled by temperament
# so a reserved student never beams. The in-game avatar is 96 px, so the
# expressions lean a little pronounced.
EXPRESSIONS = ["thinking", "happy", "worried", "victory", "defeat"]
# The edit model barely moves the eyes of a face looking at the camera,
# so "thinking" for gentle and reserved students leans on brows, squint
# and mouth; the gaze is only a bonus. Asking for the gaze alone left
# girl-01's thinking indistinguishable from her neutral portrait.
TEMPERAMENT = {
    "girl-02": "expressive", "girl-03": "expressive", "girl-05": "expressive",
    "boy-01": "expressive", "boy-03": "expressive", "boy-06": "expressive",
    "girl-01": "gentle", "girl-07": "gentle", "girl-08": "gentle",
    "boy-04": "gentle", "boy-05": "gentle", "boy-08": "gentle",
    "girl-04": "reserved", "girl-06": "reserved", "boy-02": "reserved", "boy-07": "reserved",
}
VARIANT_WORDING = {
    "expressive": {
        "thinking": "The student is thinking hard about a tricky problem: mouth closed and"
                    " pursed to one side, eyebrows furrowed, eyes looking up and to the side.",
        "happy": "The student beams with joy: a big, open-mouthed happy smile, eyes squeezed"
                 " into happy curves, rosy cheeks.",
        "worried": "The student looks anxious and in trouble: eyebrows raised and slanted"
                   " upward, eyes a little wide, closed mouth a small wobbly frown.",
        "victory": "The student cheers in triumph: eyes wide and sparkling, eyebrows raised"
                   " high, a big, delighted open-mouthed smile.",
        "defeat": "The student is bitterly disappointed: eyebrows drooping, eyes glossy and"
                  " downcast, lower lip pushed out in a frustrated pout.",
    },
    "gentle": {
        "thinking": "The student is puzzling over a hard problem: one eyebrow is raised high"
                    " and the other lowered, the eyes are narrowed, and the closed lips are"
                    " pursed and pushed clearly to one side of the face; if possible the eyes"
                    " glance up and to the side.",
        "happy": "The student smiles warmly and openly: a wide, happy smile with the lips"
                 " parted, the eyes curved into gentle happy arcs, and a faint pink blush on"
                 " the cheeks only.",
        "worried": "The student looks clearly worried: the eyebrows are raised high and"
                   " slanted upward in the middle, the eyes are a little wide and glance to"
                   " the side, and the mouth is a small, tense, wavy line.",
        "victory": "The student is delighted: bright, shining eyes, eyebrows raised, and a"
                   " big, pleased open smile showing the upper teeth.",
        "defeat": "The student is sad and disappointed: the eyes are half closed and"
                  " downcast, the eyebrows droop at the outer ends, and the mouth is a small"
                  " downturned frown.",
    },
    "reserved": {
        "thinking": "The student is in sharp, calculating concentration: the eyebrows are"
                    " lowered and drawn together into a slight frown, the eyes are narrowed"
                    " to a focused squint, and the mouth is a firm, straight closed line"
                    " pulled slightly to one side; if possible the eyes look down and to the"
                    " side.",
        "happy": "The student's composure softens into a genuine, warm closed-mouth smile:"
                 " relaxed eyebrows and eyes softened into a smile.",
        "worried": "The student is visibly uneasy: the eyebrows are drawn together and"
                   " raised in the middle, the eyes are widened and glance to the side, and"
                   " the lips are pressed firmly together.",
        "victory": "The student is quietly triumphant: a faint, confident closed-mouth smile"
                   " and steady, self-assured eyes.",
        # "Eyes closed ... a faint, bitter smile" came out as a serene,
        # contented smile on girl-04, which reads as winning.
        "defeat": "The student takes the loss hard but keeps quiet: the eyes are open and"
                  " lowered, looking down, the eyebrows are drawn together and droop at the"
                  " outer ends, and the lips are pressed into a small, tight downturned"
                  " line. No smile at all.",
    },
}
# The opponents' IDENTITY clause says "the same light skin color", which
# would lighten boy-06's brown and girl-02's tanned skin.
# Its "subtle to moderate" also left the first avatar variants almost
# unreadable at the 96 px the strip shows them at.
AVATAR_IDENTITY = IDENTITY.replace("the same light skin color", "the same skin color").replace(
    "The change of expression is subtle to moderate, natural and believable, never"
    " exaggerated or cartoonish.",
    "The new expression is clearly readable even in a small thumbnail: the eyebrows,"
    " the eyes and the mouth all visibly change. It stays natural and believable, never"
    " exaggerated or cartoonish.")
# It also only forbids skin going darker, more yellow or more tanned, so
# a happy, blushing face came out bleached (cheek G/B up ~35 levels).
AVATAR_IDENTITY = AVATAR_IDENTITY.replace(
    "never darker, more yellow or more tanned,",
    "never darker, more yellow or more tanned, and never paler, whiter, brighter or more"
    " washed out,")
assert "subtle to moderate" not in AVATAR_IDENTITY and "light skin" not in AVATAR_IDENTITY
assert "never paler" in AVATAR_IDENTITY

# Per-avatar notes that keep the edit from fighting the design.
VARIANT_NOTES = {
    "boy-03": " He wears his dark-tinted glasses for his eyes (he has amblyopia), so they"
              " stay on and exactly as they are, worn normally on his nose: never pushed"
              " up, lowered, tilted or taken off. His eyes stay hidden behind the lenses;"
              " the expression shows through his eyebrows, mouth and cheeks.",
}


# Rerolls picked during variant review; added to the derived seed.
VARIANT_SEED_OFFSETS: dict[tuple[str, str], int] = {
    ("girl-04", "thinking"): 1,  # seed 0 came out pale, with a faint mouth
}


# Approved expression variants (lossless renders in --accepted-dir),
# installed by --install-variants as player_avatars/<id>_<expr>.webp next
# to the neutral <id>.webp. Missing ones fall back to neutral in game.
ACCEPTED_VARIANTS: dict[str, dict[str, str]] = {
    "girl-01": {e: f"avatar_girl-01_{e}_00001_.png" for e in EXPRESSIONS},
    "girl-02": {e: f"avatar_girl-02_{e}_00001_.png" for e in EXPRESSIONS},
    # Three are --edit fixes of faint or uneven mouth strokes; the edit
    # output was renamed from avatar_girl-03_edit_0000N_ after each run.
    "girl-03": {
        "happy": "avatar_girl-03_happy_00001_.png",
        "thinking": "avatar_girl-03_thinking_edit_00001_.png",
        "worried": "avatar_girl-03_worried_edit_00002_.png",
        "victory": "avatar_girl-03_victory_00001_.png",
        "defeat": "avatar_girl-03_defeat_edit_00001_.png",
    },
    # thinking is the VARIANT_SEED_OFFSETS reroll; defeat is the reworded
    # reserved defeat (both _00002_ after the first batch's renders).
    "girl-04": {
        "happy": "avatar_girl-04_happy_00001_.png",
        "thinking": "avatar_girl-04_thinking_00002_.png",
        "worried": "avatar_girl-04_worried_00001_.png",
        "victory": "avatar_girl-04_victory_00001_.png",
        "defeat": "avatar_girl-04_defeat_00002_.png",
    },
    # worried is an --edit: the render kept her neutral smile.
    "girl-05": {
        "happy": "avatar_girl-05_happy_00001_.png",
        "thinking": "avatar_girl-05_thinking_00001_.png",
        "worried": "avatar_girl-05_worried_edit_00001_.png",
        "victory": "avatar_girl-05_victory_00001_.png",
        "defeat": "avatar_girl-05_defeat_00001_.png",
    },
    # Her blunt bangs hide her brows, so worried and victory are --edits
    # that move the eyes and mouth; happy is an edit that only restores
    # her beauty mark. defeat's original face was preferred over its
    # edit even without the mark.
    "girl-06": {
        "happy": "avatar_girl-06_happy_edit_00001_.png",
        "thinking": "avatar_girl-06_thinking_00001_.png",
        "worried": "avatar_girl-06_worried_edit_00001_.png",
        "victory": "avatar_girl-06_victory_edit_00001_.png",
        "defeat": "avatar_girl-06_defeat_00001_.png",
    },
    # worried kept her neutral smile and defeat was nearly neutral, so
    # both are --edits.
    "girl-07": {
        "happy": "avatar_girl-07_happy_00001_.png",
        "thinking": "avatar_girl-07_thinking_00001_.png",
        "worried": "avatar_girl-07_worried_edit_00001_.png",
        "victory": "avatar_girl-07_victory_00001_.png",
        "defeat": "avatar_girl-07_defeat_edit_00001_.png",
    },
    # thinking is her original with only the faint mouth redrawn (two
    # fuller edits failed); defeat is an --edit; worried is the original.
    "girl-08": {
        "happy": "avatar_girl-08_happy_00001_.png",
        "thinking": "avatar_girl-08_thinking_edit_00003_.png",
        "worried": "avatar_girl-08_worried_00001_.png",
        "victory": "avatar_girl-08_victory_00001_.png",
        "defeat": "avatar_girl-08_defeat_edit_00001_.png",
    },
    # The expressive wording's furrowed brows read as anger on him, so
    # worried and defeat are --edits with upward / drooping brows;
    # thinking is a calm --edit of his neutral portrait (seed offset 1).
    "boy-01": {
        "happy": "avatar_boy-01_happy_00001_.png",
        "thinking": "avatar_boy-01_thinking_edit_00003_.png",
        "worried": "avatar_boy-01_worried_edit_00001_.png",
        "victory": "avatar_boy-01_victory_00001_.png",
        "defeat": "avatar_boy-01_defeat_edit_00001_.png",
    },
    "boy-02": {e: f"avatar_boy-02_{e}_00001_.png" for e in EXPRESSIONS},
}

# Skin drift check: mean color of a cheek-height patch in the middle of
# the face (all avatars share the framing), against the neutral render.
SKIN_PATCH = "160x120+360+380"
SKIN_DRIFT_MAX = 18.0  # per channel, 0-255


def skin_color(png: Path) -> list[float]:
    out = subprocess.run(["magick", str(png), "-crop", SKIN_PATCH, "-format",
                          "%[fx:mean.r*255] %[fx:mean.g*255] %[fx:mean.b*255]", "info:"],
                         check=True, capture_output=True, text=True)
    return [float(v) for v in out.stdout.split()]


# Small accessories the approved portrait shows. A big smile or frown
# repaints the cheeks and hair, and girl-02's bandage vanished from three
# of her five variants, so each is named as something to keep. Only what
# the accepted render really shows is listed: naming one it lacks would
# add it.
KEEP_ACCESSORY = {
    "girl-01": "the small red hair ties at the ends of her two braids",
    "girl-02": "the small white adhesive bandage on her cheek",
    "girl-03": "the large white ribbon tied at her ponytail",
    "girl-04": "the small hair clip in her hair",
    "girl-05": "the black ribbons tying her two twin tails",
    "girl-06": "the small beauty mark on her cheek just below her left eye (the eye on the"
               " right side of the picture)",
    "girl-08": "the yellow star-shaped hairpin in her hair",
}


# girl-03's first thinking variant drew her mouth as one stroke that
# faded out halfway, reading as a smudge rather than a pursed mouth.
LINE_QUALITY = (
    " Every line is drawn as a clean, complete, confident stroke with the same weight and"
    " darkness as the line work in the reference image, especially the mouth, the"
    " eyebrows and the eyelids: no faint, broken, smudged, fading or half-finished lines."
)


def variant_prompt(aid: str, expr: str) -> str:
    a = AVATARS[aid]
    he = "She" if aid.startswith("girl") else "He"
    lead = f"This is {a['who']}. "
    glasses = f" {he} keeps the same {a['glasses']}." if "glasses" in a else ""
    if aid in KEEP_ACCESSORY:
        glasses += (f" {he} still has {KEEP_ACCESSORY[aid]}, exactly as in the reference"
                    " image: same size, color and position, clearly visible.")
    return (lead + VARIANT_WORDING[TEMPERAMENT[aid]][expr] + VARIANT_NOTES.get(aid, "")
            + glasses + LINE_QUALITY + KEEP + AVATAR_IDENTITY + NO_HANDS + NO_OBJECTS)


def variants(args) -> int:
    if not args.out_dir:
        print("!! --variants needs --out-dir (review first)", file=sys.stderr)
        return 1
    model = dict(DISTILLED if args.distilled else BASE)
    comfy = Comfy(args.server)
    jobs = []
    for aid in args.avatar or list(AVATARS):
        for expr in args.expression or EXPRESSIONS:
            dst = args.out_dir / f"{aid}_{expr}.webp"
            if dst.exists() and not args.force:
                continue
            jobs.append((aid, expr, dst))
    print(f"{len(jobs)} variant(s) to generate  model: {model}")
    refs: dict[str, str] = {}
    for n, (aid, expr, dst) in enumerate(jobs, 1):
        if aid not in refs:
            src = args.accepted_dir / ACCEPTED[aid]
            refs[aid] = comfy.upload(src, "avatar-ref-" + src.name, "shougibu")
        seed = (zlib.crc32(f"avatar/{aid}/{expr}".encode()) + args.seed_offset
                + VARIANT_SEED_OFFSETS.get((aid, expr), 0))
        t0 = time.time()
        png = comfy.run(build_graph(variant_prompt(aid, expr), seed, [refs[aid]],
                                    f"shougibu/avatar_{aid}_{expr}", model))
        dst.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            tmp.write(png)
            tmp.flush()
            encode(Path(tmp.name), dst, f"{WIDTH}x{HEIGHT}", Path(tmp.name), None)
            drift = max(abs(a - b) for a, b in zip(
                skin_color(Path(tmp.name)), skin_color(args.accepted_dir / ACCEPTED[aid])))
        flag = f"  !! skin drift {drift:.0f}" if drift > SKIN_DRIFT_MAX else ""
        print(f"[{n}/{len(jobs)}] {aid} {expr}  ({time.time() - t0:.0f}s){flag}", flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-a", "--avatar", action="append", choices=sorted(AVATARS),
                    help="avatar id (repeatable; default: all)")
    ap.add_argument("--force", action="store_true", help="overwrite existing avatars")
    ap.add_argument("--seed-offset", type=int, default=0, help="reroll with a different seed")
    ap.add_argument("--candidates", type=int, default=1,
                    help="seeds per avatar, from --seed-offset up (needs --out-dir when > 1)")
    ap.add_argument("--distilled", action="store_true",
                    help="distilled checkpoint (16 steps, cfg 1): fast drafts")
    ap.add_argument("--steps", type=int, help="override the sampling steps")
    ap.add_argument("--cfg", type=float, help="override the CFG scale")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--originals-dir", type=Path, default=Path.home() / "Pictures" / "samples",
                    help="where the lossless original renders live (optional)")
    ap.add_argument("--out-dir", type=Path,
                    help="write <id>_s<offset>.webp here instead of the asset folder (for review)")
    ap.add_argument("--accepted-dir", type=Path,
                    default=Path.home() / "ComfyUI" / "output" / "shougibu",
                    help="where the ACCEPTED renders live")
    ap.add_argument("--rerender", action="store_true",
                    help="render even avatars that have an ACCEPTED render")
    ap.add_argument("--edit", metavar="INSTRUCTION",
                    help="instead of a new render, edit --edit-source (a lossless render of the"
                         " one -a avatar) by this instruction; the source is the only reference."
                         " The result lands in ComfyUI's output as avatar_<id>_edit_*.png")
    ap.add_argument("--edit-source", type=Path, help="PNG to edit (see --edit)")
    ap.add_argument("--edit-style", type=Path, action="append",
                    help="with --edit: an approved render whose art style the edit should"
                         " match; repeatable, becomes <ref_image_1>, <ref_image_2>, ...")
    ap.add_argument("--install-variants", action="store_true",
                    help="encode the ACCEPTED_VARIANTS into the asset folder")
    ap.add_argument("--variants", action="store_true",
                    help="render the expression variants of the ACCEPTED avatars")
    ap.add_argument("-e", "--expression", action="append", choices=EXPRESSIONS,
                    help="with --variants: expression (repeatable; default: all)")
    args = ap.parse_args()
    if args.install_variants:
        for aid, sets in ACCEPTED_VARIANTS.items():
            if args.avatar and aid not in args.avatar:
                continue
            for expr, name in sets.items():
                dst = OUT_DIR / f"{aid}_{expr}.webp"
                if dst.exists() and not args.force:
                    continue
                encode(args.accepted_dir / name, dst, f"{WIDTH}x{HEIGHT}",
                       args.accepted_dir / name, None)
                print(f"    {dst.relative_to(REPO)}  (accepted: {name})")
        return 0
    if args.variants:
        return variants(args)
    if args.edit:
        return edit(args)
    if args.candidates > 1 and not args.out_dir:
        print("!! --candidates > 1 needs --out-dir", file=sys.stderr)
        return 1

    jobs = []
    for aid in args.avatar or sorted(AVATARS):
        for k in range(args.candidates):
            off = SEED_OFFSETS.get(aid, 0) + args.seed_offset + k
            dst = (args.out_dir / f"{aid}_s{off}.webp") if args.out_dir else OUT_DIR / f"{aid}.webp"
            if dst.exists() and not args.force:
                continue
            jobs.append((aid, off, dst))
    size = f"{WIDTH}x{HEIGHT}"
    if not args.rerender:
        todo = []
        for aid, off, dst in jobs:
            src = args.accepted_dir / ACCEPTED.get(aid, "")
            if aid not in ACCEPTED:
                todo.append((aid, off, dst))
            elif not src.is_file():
                print(f"!! {aid}: accepted render {src} not found (or pass --rerender)",
                      file=sys.stderr)
                return 1
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                encode(src, dst, size, src, None)
                shown = dst.relative_to(REPO) if dst.is_relative_to(REPO) else dst
                print(f"    {shown}  (accepted: {src.name})")
        jobs = todo
    print(f"{len(jobs)} avatar render(s) to generate")
    if not jobs:
        return 0

    model = dict(DISTILLED if args.distilled else BASE)
    if args.steps:
        model["steps"] = args.steps
    if args.cfg is not None:
        model["cfg"] = args.cfg
    print(f"    model: {model}")
    comfy = Comfy(args.server)
    refs: dict[str, list[str]] = {}
    for gender, pair in REFERENCES.items():
        refs[gender] = []
        for orig, fallback in pair:
            src = args.originals_dir / orig
            if not src.is_file():
                src = fallback
            print(f"    {gender} style reference: {src}")
            refs[gender].append(comfy.upload(src, "avatar-ref-" + src.name, "shougibu"))

    for n, (aid, off, dst) in enumerate(jobs, 1):
        seed = zlib.crc32(f"avatar/{aid}".encode()) + off
        t0 = time.time()
        png = comfy.run(build_graph(prompt_for(aid), seed, refs[aid.split("-")[0]],
                                    f"shougibu/avatar_{aid}", model))
        dst.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            tmp.write(png)
            tmp.flush()
            encode(Path(tmp.name), dst, size, Path(tmp.name), None)
        print(f"[{n}/{len(jobs)}] {dst.relative_to(REPO) if dst.is_relative_to(REPO) else dst}"
              f"  ({time.time() - t0:.0f}s)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
