# Cartoon Cursor

A tiny native macOS menu bar prototype that draws a cartoon cursor overlay that follows the mouse.

## Features

- Menu bar toggle for the overlay.
- Optional system cursor hiding.
- Custom PNG/JPG/GIF/TIFF image selection.
- Built-in default cartoon cursor.
- Effect menu with sparkles, rings, trail, combined sparkles + trail, and off.
- Effect color menu with automatic sticker color sampling or separate custom 4-color palettes for trail, click, and sparkle effects.
- Each custom color slot is independent; the four colors in a group are cycled across that effect's particles.
- Trail, click, and sparkle palettes open in a compact editor window so all four colors can be edited together.
- Palette editor changes are staged until Apply, so dragging the color picker does not immediately overwrite saved colors.
- Palette rows use independent Hex/R/G/B inputs instead of shared color controls, so editing one row only changes that row.
- Palette input updates the preview immediately; Apply saves the staged palette to the effect.
- While editing, only the current row is refreshed.
- Optional native cursor effects mode for keeping the original macOS cursor while showing click/trail effects.
- Effects sample accent colors from the selected sticker by default, including black/dark colors.
- Sticker cover mode: custom images preserve their original aspect ratio, and the selected size is the maximum edge. The sticker is anchored near the system cursor tip to visually cover the native cursor.

## Build

```sh
./scripts/package.sh
```

The packaged app is written to `../../outputs/CartoonCursor.app`, and a zip is written to `../../outputs/CartoonCursor.zip`.

## Notes

macOS does not provide a friendly public API for replacing the system cursor globally from a normal app. This prototype uses a transparent, click-through overlay window instead. It is good for everyday customization and demos, but secure screens, login windows, and some full-screen apps may still show macOS behavior.
