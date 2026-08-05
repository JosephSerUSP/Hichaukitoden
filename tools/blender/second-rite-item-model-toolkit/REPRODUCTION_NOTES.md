# Reproduction Notes

These notes preserve the non-obvious build issues encountered while creating the expanded library.

## Blender version

Validated with Blender 5.0.1, build hash `a3db93c5b259`.

## 1. Binary discovery under GitHub Actions

Searching all of `/tmp` with `find` returned permission errors for protected systemd directories. Under `set -euo pipefail`, that made the step fail even though Blender had been found.

Use a narrowed search:

```bash
find /tmp/blender-* -maxdepth 2 -type f -name blender -perm -111 2>/dev/null | head -1
```

## 2. Eevee engine identifier

The downloaded Blender 5.0.1 build accepted `BLENDER_EEVEE`, not `BLENDER_EEVEE_NEXT`.

The final generator uses Workbench for its validation preview, avoiding this dependency entirely.

## 3. Headless EGL/OpenGL

Blender preview rendering aborted without `libEGL.so.1` on the Ubuntu runner.

Install:

```bash
sudo apt-get install -y --no-install-recommends \
  libegl1 libgl1-mesa-dri libgbm1 xvfb xauth
```

Run Blender through:

```bash
xvfb-run -a blender --background --python build_expanded_item_library.py
```

## 4. Software-rendered Eevee was too slow

A 2100×2100 Eevee gallery was expensive under software rendering. The final contact sheet uses Workbench with material colors, studio lighting, shadows, and cavity shading at 70% render scale.

The `.blend`, geometry, materials, and OBJ files are unaffected by the preview renderer choice.

## 5. Output assertions

The validated pipeline checks:

```text
second_rite_item_model_library_expanded.blend exists and is nonempty
second_rite_item_model_library_expanded_preview.png exists and is nonempty
exactly 53 .obj files exist
all exported OBJ files exceed a minimal nontrivial size
```

## 6. GitHub artifact retention

The temporary build workflow used a short artifact retention window. This toolkit is the durable source package; do not depend on old Actions artifacts remaining available.
