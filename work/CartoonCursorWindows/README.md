# Cartoon Cursor for Windows

A Windows tray-app version of Cartoon Cursor. It draws a transparent click-through overlay above the desktop, follows the mouse, and shows a cartoon sticker with optional click/trail/sparkle effects.

## Features

- Windows tray menu.
- Transparent click-through sticker overlay.
- Sticker Manager with multi-import, switch, delete-current, and delete-by-item.
- PNG/JPG/GIF/BMP import. GIF stickers animate.
- Cursor sizes from 32 px to 256 px.
- Effects: Sparkles + Trail, Sparkles, Trail, Rings, Off.
- Native cursor effects that can stay visible even when the sticker is disabled.
- Separate sticker and native cursor color palettes for trail, click/ring, and sparkle particles.
- Palette editor with four color slots, Hex/RGB inputs, and preset swatches.
- Sticker walk follow, frame animation for GIFs/static stickers, speed choices, and amplitude choices. Frame animation keeps playing smoothly while walk follow is enabled.
- Best-effort native cursor hiding using the Windows cursor display counter.

## Build On Windows

Install the .NET 8 SDK, then run:

```powershell
cd work\CartoonCursorWindows
.\scripts\package.ps1
```

The packaged app is written to:

```text
outputs\windows\CartoonCursor-win-x64.zip
```

For Windows on ARM:

```powershell
.\scripts\package.ps1 -Runtime win-arm64
```

## Notes

- This is a separate Windows implementation; the macOS AppKit code cannot be reused directly.
- Windows GDI+ reliably animates GIF files. APNG files may import as a static PNG depending on the Windows runtime, so use GIF for animated stickers on Windows for now.
- Some fullscreen games or protected windows may draw above the overlay or force their own cursor behavior.
