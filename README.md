# Cartoon Cursor Workspace

This repository contains native Cartoon Cursor app prototypes and helper scripts used to prepare transparent sticker images.

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
Palette groups open in a compact editor window so all four colors can be edited together.
Palette editor changes are staged until Apply, so color picker drags do not immediately overwrite saved colors.
Palette rows use independent Hex/R/G/B inputs, so editing one row only changes that row.
Palette input updates the preview immediately; Apply saves the staged palette to the effect.

## Windows App

The Windows tray app source lives in `work/CartoonCursorWindows`.

Build it on Windows with the .NET 8 SDK:

```powershell
cd work\CartoonCursorWindows
.\scripts\package.ps1
```

The Windows package script writes generated artifacts to `outputs/windows/`.

You can also verify the Windows build in GitHub Actions without installing Windows locally:

1. Push to GitHub.
2. Open the repository's Actions tab.
3. Open the latest "Windows Build" run.
4. Download the `CartoonCursor-win-x64` or `CartoonCursor-win-arm64` artifact.

## Sticker Cutout Helpers

The `work/cutout_*.py` scripts are local helpers for cutting sticker sheets into transparent PNG assets.

Generated images, packaged apps, and zip files are ignored by git.
