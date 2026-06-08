# Cartoon Cursor

A tiny native macOS menu bar prototype that draws a cartoon cursor overlay that follows the mouse.

## Features

- Menu bar toggle for the overlay.
- Optional system cursor hiding.
- Custom PNG/JPG/GIF/TIFF image selection.
- Built-in default cartoon cursor.
- Effect menu with sparkles, rings, trail, combined sparkles + trail, and off.
- Optional native cursor effects mode for keeping the original macOS cursor while showing click/trail effects.
- Effects sample accent colors from the selected sticker, including black/dark colors.
- Sticker cover mode: custom images preserve their original aspect ratio, and the selected size is the maximum edge. The sticker is anchored near the system cursor tip to visually cover the native cursor.

## Build

```sh
./scripts/package.sh
```

The packaged app is written to `../../outputs/CartoonCursor.app`, and a zip is written to `../../outputs/CartoonCursor.zip`.

## Notes

macOS does not provide a friendly public API for replacing the system cursor globally from a normal app. This prototype uses a transparent, click-through overlay window instead. It is good for everyday customization and demos, but secure screens, login windows, and some full-screen apps may still show macOS behavior.
