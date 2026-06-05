#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


SOURCE = Path("/Users/xiuluo/Library/Application Support/LarkShell/sdk_storage/063286b6def05ac6f244916fa252e334/resources/images/img_v3_0212c_a721afa1-b9e9-4eae-ae4c-3b922750cf0g.jpg")
OUT_DIR = Path("outputs/hamster_cutouts")
COLUMNS = 4


def light_background_mask(rgb: np.ndarray, min_light: int = 210, max_span: int = 58) -> np.ndarray:
    values = rgb.astype(np.int16)
    span = values.max(axis=2) - values.min(axis=2)
    return (values.min(axis=2) >= min_light) & (span <= max_span)


def background_color(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    if np.count_nonzero(bg) > 20:
        return np.median(rgb[bg], axis=0).astype(np.float32)
    return np.array([238, 238, 238], dtype=np.float32)


def flood_background(passable: np.ndarray) -> np.ndarray:
    h, w = passable.shape
    visited = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def push(y: int, x: int) -> None:
        if y < 0 or y >= h or x < 0 or x >= w:
            return
        if visited[y, x] or not passable[y, x]:
            return
        visited[y, x] = True
        queue.append((y, x))

    for x in range(w):
        push(0, x)
        push(h - 1, x)
    for y in range(h):
        push(y, 0)
        push(y, w - 1)

    while queue:
        y, x = queue.popleft()
        push(y + 1, x)
        push(y - 1, x)
        push(y, x + 1)
        push(y, x - 1)

    return visited


def content_bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def pad_bbox(
    bbox: tuple[int, int, int, int],
    pad: int,
    width: int,
    height: int,
) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = bbox
    return max(0, x1 - pad), max(0, y1 - pad), min(width, x2 + pad), min(height, y2 + pad)


def detect_row_bands(seed: np.ndarray, min_y: int, max_y: int) -> list[tuple[int, int]]:
    working = seed.copy()
    working[:min_y, :] = False
    working[max_y:, :] = False
    projection = working.sum(axis=1)
    threshold = max(18, int(seed.shape[1] * 0.035))
    active = projection > threshold
    closed = np.convolve(active.astype(np.int16), np.ones(35, dtype=np.int16), mode="same") > 0

    bands: list[tuple[int, int]] = []
    start: int | None = None
    for index, value in enumerate(closed):
        if value and start is None:
            start = index
        elif not value and start is not None:
            end = index - 1
            if end - start >= 50:
                bands.append((start, end))
            start = None
    if start is not None and len(closed) - start >= 50:
        bands.append((start, len(closed) - 1))
    return bands


def make_alpha(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    bg = light_background_mask(rgb)
    bg_rgb = background_color(rgb, bg)
    values = rgb.astype(np.float32)
    span = values.max(axis=2) - values.min(axis=2)
    diff = np.max(np.abs(values - bg_rgb), axis=2)
    seed = (~bg) | ((span > 34) & (diff > 14))

    seed_image = Image.fromarray((seed.astype(np.uint8) * 255), mode="L")
    blocked = np.asarray(seed_image.filter(ImageFilter.MaxFilter(9))) > 0
    outside = flood_background(bg & ~blocked)
    enclosed_light = bg & ~outside

    edge_strength = np.maximum(diff, span * 0.8)
    soft_alpha = np.clip((edge_strength - 8.0) * 12.0, 0, 255).astype(np.uint8)
    soft_alpha[outside & bg] = 0

    alpha = soft_alpha
    alpha[seed] = np.maximum(alpha[seed], 235)
    solid_backing = blocked | enclosed_light
    alpha[solid_backing] = 255

    # Remove flat bright background chunks that are still connected to crop edges.
    near_white = (values.min(axis=2) > 242) & (span < 22)
    white_blocked = blocked
    outside_white = flood_background(near_white & ~white_blocked)
    alpha[outside_white & ~solid_backing] = 0
    return alpha, bg_rgb, seed, solid_backing


def decontaminate_edges(rgb: np.ndarray, alpha: np.ndarray, bg_rgb: np.ndarray) -> np.ndarray:
    corrected = rgb.astype(np.float32).copy()
    a = alpha.astype(np.float32) / 255.0
    partial = (alpha > 0) & (alpha < 245)
    safe_a = np.maximum(a, 0.05)
    for channel in range(3):
        channel_values = (corrected[:, :, channel] - (1.0 - safe_a) * bg_rgb[channel]) / safe_a
        corrected[:, :, channel] = np.where(partial, channel_values, corrected[:, :, channel])
    return np.clip(corrected, 0, 255).astype(np.uint8)


def remove_small_pale_artifacts(alpha: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    mask = alpha > 0
    h, w = mask.shape
    visited = np.zeros((h, w), dtype=bool)
    cleaned = alpha.copy()

    for start_y in range(h):
        for start_x in range(w):
            if not mask[start_y, start_x] or visited[start_y, start_x]:
                continue
            queue = [(start_y, start_x)]
            visited[start_y, start_x] = True
            ys: list[int] = []
            xs: list[int] = []
            for y, x in queue:
                ys.append(y)
                xs.append(x)
                for next_y, next_x in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if (
                        0 <= next_y < h
                        and 0 <= next_x < w
                        and mask[next_y, next_x]
                        and not visited[next_y, next_x]
                    ):
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))

            if len(xs) >= 70:
                continue
            y_index = np.asarray(ys)
            x_index = np.asarray(xs)
            values = rgb[y_index, x_index, :].astype(np.float32)
            span = values.max(axis=1) - values.min(axis=1)
            mean_rgb = values.mean(axis=0)
            if mean_rgb.min() > 225 and float(span.mean()) < 32:
                cleaned[y_index, x_index] = 0
    return cleaned


def save_cutout(source_rgb: np.ndarray, bbox: tuple[int, int, int, int], output: Path) -> Image.Image:
    x1, y1, x2, y2 = bbox
    rgb = source_rgb[y1:y2, x1:x2, :]
    alpha, bg_rgb, seed, solid_backing = make_alpha(rgb)
    alpha = remove_small_pale_artifacts(alpha, rgb)
    bg_like = light_background_mask(rgb)
    rgb = rgb.copy()
    rgb[solid_backing & bg_like & ~seed] = np.array([255, 255, 255], dtype=np.uint8)
    trim = content_bbox(alpha > 0)
    if trim is not None:
        tx1, ty1, tx2, ty2 = pad_bbox(trim, 6, rgb.shape[1], rgb.shape[0])
        rgb = rgb[ty1:ty2, tx1:tx2, :]
        alpha = alpha[ty1:ty2, tx1:tx2]
    corrected = decontaminate_edges(rgb, alpha, bg_rgb)
    image = Image.fromarray(np.dstack([corrected, alpha]), mode="RGBA")
    image.save(output)
    return image


def checkerboard(size: tuple[int, int], tile: int = 14) -> Image.Image:
    image = Image.new("RGB", size, "#f5f5f5")
    draw = ImageDraw.Draw(image)
    w, h = size
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            if ((x // tile) + (y // tile)) % 2 == 0:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e7e7e7")
    return image


def make_preview(paths: list[Path], output: Path, columns: int = 4, solid: bool = False) -> None:
    thumb = 160
    label_h = 24
    gap = 18
    rows = math.ceil(len(paths) / columns)
    width = columns * thumb + (columns + 1) * gap
    height = rows * (thumb + label_h) + (rows + 1) * gap
    preview = Image.new("RGB", (width, height), "#9fd0ff") if solid else checkerboard((width, height))
    draw = ImageDraw.Draw(preview)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    except Exception:
        font = ImageFont.load_default()

    for index, path in enumerate(paths):
        sticker = Image.open(path).convert("RGBA")
        sticker.thumbnail((thumb, thumb), Image.Resampling.LANCZOS)
        row = index // columns
        col = index % columns
        x = gap + col * (thumb + gap)
        y = gap + row * (thumb + label_h + gap)
        preview.paste(sticker, (x + (thumb - sticker.width) // 2, y + (thumb - sticker.height) // 2), sticker)
        draw.text((x, y + thumb + 5), path.stem, fill="#111111" if solid else "#333333", font=font)
    preview.save(output)


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    rgb = np.asarray(source)
    h, w = rgb.shape[:2]
    bg = light_background_mask(rgb)
    seed = ~bg
    bands = detect_row_bands(seed, min_y=520, max_y=1930)

    stickers_dir = OUT_DIR / "stickers"
    if stickers_dir.exists():
        shutil.rmtree(stickers_dir)
    stickers_dir.mkdir(parents=True, exist_ok=True)

    transparent_sheet = Image.new("RGBA", source.size, (255, 255, 255, 0))
    paths: list[Path] = []
    metadata: list[dict[str, object]] = []
    index = 1
    for row_index, (band_y1, band_y2) in enumerate(bands, start=1):
        for col_index in range(1, COLUMNS + 1):
            cell_x1 = int(round((col_index - 1) * w / COLUMNS))
            cell_x2 = int(round(col_index * w / COLUMNS))
            cell = seed[band_y1:band_y2 + 1, cell_x1:cell_x2]
            bbox = content_bbox(cell)
            if bbox is None:
                continue
            lx1, ly1, lx2, ly2 = bbox
            global_bbox = (cell_x1 + lx1, band_y1 + ly1, cell_x1 + lx2, band_y1 + ly2)
            gx1, gy1, gx2, gy2 = global_bbox
            if (gx2 - gx1) * (gy2 - gy1) < 1800:
                continue
            padded = pad_bbox(global_bbox, 24, w, h)
            output = stickers_dir / f"sticker_{index:02d}.png"
            sticker = save_cutout(rgb, padded, output)
            transparent_sheet.paste(sticker, (padded[0], padded[1]), sticker)
            paths.append(output)
            metadata.append({"file": output.name, "row": row_index, "column": col_index, "bbox": padded, "size": sticker.size})
            index += 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    make_preview(paths, OUT_DIR / "sticker_cutout_preview.png", columns=4, solid=False)
    make_preview(paths, OUT_DIR / "sticker_cutout_preview_solid.png", columns=4, solid=True)
    transparent_sheet.save(OUT_DIR / "sticker_sheet_transparent.png")
    archive = shutil.make_archive(str(OUT_DIR / "sticker_cutouts"), "zip", root_dir=stickers_dir)
    (OUT_DIR / "sticker_cutouts_metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(
        {
            "count": len(paths),
            "stickers_dir": str(stickers_dir),
            "preview": str(OUT_DIR / "sticker_cutout_preview.png"),
            "solid_preview": str(OUT_DIR / "sticker_cutout_preview_solid.png"),
            "sheet": str(OUT_DIR / "sticker_sheet_transparent.png"),
            "zip": archive,
            "metadata": str(OUT_DIR / "sticker_cutouts_metadata.json"),
        },
        ensure_ascii=False,
        indent=2,
    ))


if __name__ == "__main__":
    main()
