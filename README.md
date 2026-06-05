# Cartoon Cursor Workspace

This repository contains a small native macOS menu bar app prototype and helper scripts used to prepare transparent sticker images.

## App

The macOS app source lives in `work/CartoonCursor`.

```sh
cd work/CartoonCursor
./scripts/package.sh
```

The package script builds a universal macOS app and writes generated artifacts to `outputs/`.

## Sticker Cutout Helpers

The `work/cutout_*.py` scripts are local helpers for cutting sticker sheets into transparent PNG assets.

Generated images, packaged apps, and zip files are ignored by git.
