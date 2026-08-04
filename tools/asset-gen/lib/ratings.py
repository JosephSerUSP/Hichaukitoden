"""Owner scores for staged variants, and the joins that make them useful.

The seam metric and the chroma check can both pass on a picture nobody wants.
They measure whether a texture tiles and whether it decoded sanely; neither has
an opinion about whether it looks like the game. This module is where that
opinion is kept, so a checkpoint or a LoRA can be chosen on taste and tiling
together instead of tiling alone.

The store is one flat JSON file of {key: judgement} rather than a row per run
directory. Staging directories are disposable and get swept; a judgement about
"the mature/resevil vault at depth 0.60" should outlive the render it was made
on, and a single file is also the thing an interrupted rating session can be
resumed from without reconciliation.
"""

from __future__ import annotations

import json
import os
import statistics
import threading
import time

from . import classes


# The store lives OUTSIDE out/, and that placement is the whole point.
#
# It used to sit in out/ beside the runs it judges, which reads as tidy and was
# wrong twice over: out/ is gitignored and wholly untracked, so the file had no
# history and no backup, and out/ is by design the disposable directory -- a
# `git clean -fdx`, the routine way to reset a worktree here, deletes it without
# a word. Every other thing in out/ can be re-rendered by the GPU in an hour.
# The owner's judgements cannot be regenerated at any price, and they were lost
# that way twice before anyone noticed the file was sitting in the bin.
#
# So: tracked, committed, and outside the sweep's reach.
STORE = os.path.join(classes.ROOT, "tools", "asset-gen", "ratings.json")

# Where it used to live. Read on load and merged, never written, so a store
# left behind by an older checkout (or one mid-rating when this landed) still
# contributes its scores instead of silently vanishing a second time.
LEGACY_STORE = os.path.join(classes.ROOT, "tools", "asset-gen", "out", "ratings.json")

_STORE_LOCK = threading.Lock()

# Deliberately few, deliberately about causes. "3 stars" says a picture is
# mediocre; "3 stars, lit" says the negative prompt is losing, which is a thing
# that can be fixed. Each is a failure mode the checkpoint sweep actually
# produced, so every tag has already earned its place.
# (id, keyboard shortcut, what it means). The shortcut is declared rather than
# taken from the first letter, because the set has outgrown the alphabet's
# convenience: blank/busy and face/flat collide, and silently giving two tags
# the same key would make one of them unreachable.
# (id, shortcut, group, meaning). The GROUP exists because the owner's own
# reading was right: "low prompt adherence", "hallucination" and "incoherent
# imagery" are one question wearing three hats. Grouping says so on screen, so
# picking between `material`, `picture`, `fragment` and `face` is choosing HOW
# the brief was missed rather than guessing which of four unrelated things is
# meant. Where the distinction is genuinely unclear, any tag in the right group
# is good enough -- the group is what the analysis rolls up to.
TAGS = [
    # Does it tile? Only the first is measurable; see the note on `repeat`.
    ("seam", "s", "tiling", "the EDGE does not match -- a discontinuity where tiles butt"),
    ("repeat", "r", "tiling", "tiles obviously -- the border reads as a border even "
                              "when matched, or a landmark feature repeats visibly"),
    # Is the light right? The engine lights a scene but never occludes a texture.
    #
    # `flat` lives HERE, not under brief, and it absorbed `noao`. The owner was
    # reaching for it to mean "this does not look like it has depth", which is
    # the same complaint `noao` was coined for from the other end: a surface
    # reads as dimensional because its recesses are darker, so no occlusion and
    # no apparent depth are one observation, not two. Two words for one thing is
    # what made choosing between them feel wrong.
    ("harsh", "h", "light", "harsh direct light, cast shadow or a visible light direction"),
    ("flat", "f", "light", "does not look like it has depth -- recesses are not "
                           "darker than raised faces, so it reads as a flat sheet"),
    # Did it build what was asked for? All of these are "missed the brief".
    ("material", "m", "brief", "not the material asked for"),
    # Renamed from the old `flat`. This is a REGISTRATION failure -- the depth
    # map was ignored -- which is invisible in the picture alone: an image can
    # look beautifully three-dimensional and still follow none of the geometry
    # it was conditioned on. Sharing a name with the appearance complaint meant
    # neither could be counted.
    ("unguided", "d", "brief", "the depth map had no visible effect -- the relief "
                               "does not follow the geometry it was given"),
    ("fragment", "g", "brief", "relief that does not follow the layout, or breaks "
                               "into disconnected pieces"),
    ("picture", "p", "brief", "painted a scene or composition instead of a material"),
    ("perspective", "v", "brief", "implies a receding surface or camera perspective "
                                  "when the material should be flat, aerial or head-on"),
    ("face", "a", "brief", "a face or figure hallucinated in the rock"),
    # Whose fault is it? Everything in `brief` blames the MODEL for missing what
    # was asked. This one says the asking was wrong: the render is a faithful
    # execution of a brief that requested the wrong thing, so no checkpoint or
    # LoRA can fix it and none should be scored down for it.
    #
    # Coined for a scale failure the owner hit on 04.08: "rubble" returns a heap
    # of little stones rather than a wall, or a square metre of floor -- the
    # picture is good and obeys the word, and the word was the wrong word.
    ("prompt", "w", "authoring", "the picture obeys the brief and the BRIEF was "
                                 "wrong -- wrong scale, wrong word, our fault not "
                                 "the model's"),
    # Is the image itself broken? These are faults, not judgements, and the
    # first two are already measured -- tag them so a checkpoint is not scored
    # down for something a prompt or a reroll fixes.
    ("burned", "u", "broken", "blown out, over-saturated or malformed"),
    ("blank", "e", "broken", "dead margin -- a flat empty strip along one edge"),
    ("text", "t", "broken", "letters, banner or watermark"),
    # Pure taste. Nothing measures these and nothing should.
    ("palette", "c", "taste", "colours are off for the game -- a judgement, not a fault"),
    ("busy", "b", "taste", "too detailed or noisy for the tile"),
]

GROUP_ORDER = ["tiling", "light", "brief", "authoring", "broken", "taste"]

# `lit` used to mean "baked lighting or cast shadow" and covered both of the
# first two tags at once. That conflation is exactly the thing the owner caught:
# baked AMBIENT OCCLUSION is wanted, because the engine lights a scene but never
# adds occlusion to a texture, while baked DIRECT light is not, because the
# engine owns direction. One tag could not say which had gone wrong, so ratings
# carrying it are ambiguous and `gen.py ratings` prints them under this name to
# keep them visibly distinct from the two that replaced it.
LEGACY_TAGS = {
    "lit": "lit(ambiguous)",
    # Same story as `lit`: one key answering two questions. Old `colour` ratings
    # cannot be read as either `palette` or `burned`, so they are shown as
    # neither.
    "colour": "colour(ambiguous)",
}

# `seam` kept its name through the split but not its meaning: before this
# moment it was the only tiling tag, so it absorbed both a mismatched edge and
# a texture that merely repeats too visibly. Renaming it would have been
# cleaner, but it would also have thrown away the narrow readings it does
# contain. Instead the old ones are relabelled by TIMESTAMP, so a rate computed
# over them is never quietly presented as a measurement of edge mismatch.
TAG_SPLIT_AT = "2026-08-03T23:59:59"
SPLIT_TAGS = {"seam": "seam(pre-split)"}


def display_tag(tag, judged_at):
    if tag in SPLIT_TAGS and (judged_at or "") < TAG_SPLIT_AT:
        return SPLIT_TAGS[tag]
    return LEGACY_TAGS.get(tag, tag)


def key(run_name, variant_index):
    return f"{run_name}#{variant_index}"


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}


def load():
    """Every judgement on record, the legacy store folded in underneath.

    Merge order matters: the current store wins a key collision, because a
    re-rating recorded since the move is by definition the newer opinion.
    """
    store = _read(LEGACY_STORE)
    store.update(_read(STORE))
    return store


def save(store):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    tmp = STORE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(store, handle, indent=1, sort_keys=True)
    os.replace(tmp, STORE)
    return STORE


SCORE_MIN, SCORE_MAX = 0, 6

# 1-5 is the ordinary scale and the two ends are deliberately not more of it.
#
# 0 is not "worse than 1". It is a flag: something failed catastrophically and
# wants a person to look at it, not a star to be averaged into a column. 6 is
# its mirror -- not "better than 5" but "I actually really like this", the
# handful worth finding again later.
#
# Both are rare by construction, so a mean over a column containing one moves
# further than the judgement intends. Read them as counts as well as values.
SCORE_LABELS = {0: "catastrophe", 6: "love it"}


def record(run_name, variant_index, score, tags=None, note=None):
    """Write one judgement. Re-rating the same variant replaces the old one.

    `note` is free text and deliberately unconstrained. The tags are a closed
    vocabulary because they have to aggregate; a note is for the thing no tag
    can say yet -- "the lighting on these walls reads OUTDOORS" is a real,
    repeating fault with no tag to its name, and the note is where such a
    pattern gets recorded before anyone knows what to call it. Several notes
    saying the same thing is the evidence that a tag should exist.
    """
    if score is not None and not SCORE_MIN <= int(score) <= SCORE_MAX:
        raise ValueError(f"score must be {SCORE_MIN}-{SCORE_MAX}")
    # The HTTP server is threaded and the rater can submit adjacent scores
    # faster than the filesystem round-trip. Keep the read-modify-write as
    # one operation or the last request can overwrite its sibling's rating.
    with _STORE_LOCK:
        store = load()
        judgement = {
            "score": None if score is None else int(score),
            "tags": sorted(set(tags or [])),
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }
        # Absent rather than empty: the store is read by eye often enough that
        # a blank field on 400 judgements is noise, and `note in judgement` is
        # the natural way to ask for the ones that have something to say.
        text = (note or "").strip()
        if text:
            judgement["note"] = text
        store[key(run_name, variant_index)] = judgement
        save(store)
        return store


def notes(store=None):
    """Every note on record, newest first, as (key, when, score, tags, text).

    Notes exist to be re-read -- a note nobody ever sees again is a diary, not
    an instrument -- so reading them back is a first-class operation and not
    something to be reconstructed from the raw JSON each time.
    """
    store = load() if store is None else store
    rows = [(k, v.get("at") or "", v.get("score"), v.get("tags") or [], v["note"])
            for k, v in store.items() if (v.get("note") or "").strip()]
    rows.sort(key=lambda row: row[1], reverse=True)
    return rows


def facets(manifest, variant):
    """The knobs a judgement should be attributable to.

    Read from the manifest rather than parsed out of the run name. Job names
    are an experiment's private convention and change between sweeps; the
    provider block is written by the generator itself and means the same thing
    in every run, so ratings from different experiments aggregate together.
    """
    provider = manifest.get("provider") or {}
    sampling = provider.get("sampling") or {}
    loras = sampling.get("loras") or []
    height = provider.get("heightControl") or ""
    score = variant.get("tileScore") or {}
    quality = variant.get("rawQuality") or {}
    return {
        "class": manifest.get("class"),
        "model": provider.get("model"),
        "lora": loras[0]["name"] if loras else "control",
        "depthWeight": provider.get("heightControlWeight"),
        "heightMap": os.path.splitext(os.path.basename(height))[0] or "none",
        "seam": score.get("x"),
        "centre": score.get("centre_x"),
        "chroma": quality.get("highChromaRatio"),
        "verdict": quality.get("verdict"),
        # Surfaced so a dead margin is visible as a MEASURED fault before the
        # score is given, rather than being absorbed into a low number.
        "blank": quality.get("blank"),
        "blankEdge": quality.get("blankEdgeFraction"),
    }


def _manifest(path):
    try:
        with open(os.path.join(path, "manifest.json"), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None


def _context_url(run_path, entry, variant):
    """The room preview, trusting the file on disk over the manifest key.

    Older runs were rendered before the manifest recorded the preview, so the
    PNG is there and the key is not. Checking the disk means those runs get
    their room back without a re-render.
    """
    name = variant.get("context") or f"context-{variant.get('index')}.png"
    if os.path.isfile(os.path.join(run_path, name)):
        return f"/out/{entry}/{name}"
    return None


def queue(staging_root, prefix="", rated=False):
    """Every staged variant, newest run first, as rateable items.

    Unrated items come first regardless of age: the point of the queue is to
    finish an opinion, and burying twenty new renders under two hundred already
    judged ones is how a rating pass stops getting done.
    """
    store = load()
    items = []
    # By modification time, not by name. Run directories are named
    # "<class>-<job>-<stamp>", so sorting the names sorts by class first and
    # buries a fresh texturePiece batch under every wallPiece ever staged.
    entries = sorted((entry for entry in os.listdir(staging_root)
                      if os.path.isdir(os.path.join(staging_root, entry))),
                     key=lambda entry: os.path.getmtime(
                         os.path.join(staging_root, entry)),
                     reverse=True)
    for entry in entries:
        run_path = os.path.join(staging_root, entry)
        if prefix and prefix not in entry:
            continue
        manifest = _manifest(run_path)
        if not manifest:
            continue
        for variant in manifest.get("variants") or []:
            index = variant.get("index")
            judgement = store.get(key(entry, index))
            if judgement and not rated:
                continue
            items.append({
                "key": key(entry, index),
                "run": entry,
                "variant": index,
                "name": manifest.get("name"),
                "image": f"/out/{entry}/{variant.get('file')}",
                "raw": f"/out/{entry}/{variant.get('raw', '')}",
                "context": _context_url(run_path, entry, variant),
                "contextLabel": variant.get("contextLabel"),
                "tileAxes": manifest.get("tileAxes", "xy"),
                "facets": facets(manifest, variant),
                "judgement": judgement,
            })
    items.sort(key=lambda item: item["judgement"] is not None)
    return items


def families(staging_root):
    """The batches actually on disk, with how much of each is still unrated.

    A free-text filter is only usable by someone who already knows what to
    type, and nothing on the page said. These are derived from the staged job
    names rather than declared, so an experiment added later appears here
    without anyone remembering to register it.

    Grouping is by the first name token, which is the experiment. The one
    exception is spelled out in QUALIFIERS: `kit_` and `kit_ao_` are two arms
    of a deliberate A/B and have to be separable, whereas `kit_wall_` is a
    surface INSIDE an arm and splitting on it would bury the row that matters.
    A purely structural rule cannot tell those apart -- both are "second token"
    -- so the exception is named rather than inferred.
    """
    QUALIFIERS = {"ao"}
    MINIMUM = 8
    store = load()
    counts = {}
    for entry in os.listdir(staging_root):
        run_path = os.path.join(staging_root, entry)
        if not os.path.isdir(run_path):
            continue
        manifest = _manifest(run_path)
        if not manifest:
            continue
        name = manifest.get("name") or ""
        tokens = name.split("_")
        if not tokens[0]:
            continue
        candidates = [tokens[0] + "_"]
        if len(tokens) > 1 and tokens[1] in QUALIFIERS:
            candidates.append("_".join(tokens[:2]) + "_")
        for candidate in candidates:
            bucket = counts.setdefault(candidate, {"total": 0, "rated": 0})
            for variant in manifest.get("variants") or []:
                bucket["total"] += 1
                if store.get(key(entry, variant.get("index"))):
                    bucket["rated"] += 1

    rows = []
    for candidate, bucket in counts.items():
        # One-off and exploratory runs are not batches and only crowd the list.
        if bucket["total"] < MINIMUM:
            continue
        rows.append({
            "prefix": candidate,
            "total": bucket["total"],
            "rated": bucket["rated"],
            "unrated": bucket["total"] - bucket["rated"],
        })
    rows.sort(key=lambda row: (-row["unrated"], row["prefix"]))
    return rows


def leaderboard(staging_root, prefix="", facet="model"):
    """Mean owner score per facet value, next to what the metrics said.

    Both columns are printed on purpose. Where they agree the choice is easy;
    where they disagree is the only interesting part of the table, and averaging
    them into one number would hide exactly that.
    """
    store = load()
    buckets = {}
    for entry in os.listdir(staging_root):
        run_path = os.path.join(staging_root, entry)
        if not os.path.isdir(run_path) or prefix and prefix not in entry:
            continue
        manifest = _manifest(run_path)
        if not manifest:
            continue
        for variant in manifest.get("variants") or []:
            judgement = store.get(key(entry, variant.get("index")))
            if not judgement or judgement.get("score") is None:
                continue
            values = facets(manifest, variant)
            bucket = buckets.setdefault(str(values.get(facet)),
                                        {"scores": [], "seam": [], "tags": {}})
            bucket["scores"].append(judgement["score"])
            if values["seam"] is not None and values["centre"]:
                bucket["seam"].append(values["seam"] / values["centre"])
            for tag in judgement.get("tags") or []:
                tag = display_tag(tag, judgement.get("at"))
                bucket["tags"][tag] = bucket["tags"].get(tag, 0) + 1

    rows = []
    for value, bucket in buckets.items():
        rows.append({
            "value": value,
            "n": len(bucket["scores"]),
            "score": round(statistics.mean(bucket["scores"]), 2),
            "seamRatio": (round(statistics.median(bucket["seam"]), 2)
                          if bucket["seam"] else None),
            "tags": dict(sorted(bucket["tags"].items(),
                                key=lambda item: -item[1])[:3]),
        })
    rows.sort(key=lambda row: -row["score"])
    return rows
