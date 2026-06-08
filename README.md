# Cartoon Cursor Workspace

This repository contains a small native macOS menu bar app prototype and helper scripts used to prepare transparent sticker images.

## App

The macOS app source lives in `work/CartoonCursor`.

```sh
cd work/CartoonCursor
./scripts/package.sh
```

The package script builds a universal macOS app and writes generated artifacts to `outputs/`.

The app includes a separate native cursor effects toggle, so the original macOS cursor can keep click/trail effects even when the cartoon sticker overlay is hidden.
Effect colors can be sampled from the selected sticker automatically or set with separate custom palettes for trail, click, and sparkle effects.
Each custom palette has four independent color slots that are cycled across that effect's particles.

## Sticker Cutout Helpers

The `work/cutout_*.py` scripts are local helpers for cutting sticker sheets into transparent PNG assets.

Generated images, packaged apps, and zip files are ignored by git.
