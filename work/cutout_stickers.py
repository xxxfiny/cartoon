#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter


def near_white_mask(rgb: np.ndarray) -> np.ndarray:
    values = rgb.astype(np.int16)
    channel_span = values.max(axis=2) - values.min(axis=2)
    min_channel = values.min(axis=2)
    # JPEG compression makes the white UI background slightly uneven.
    return (min_channel > 241) & (channel_span < 24)


def near_black_mask(rgb: np.ndarray) -> np.ndarray:
    return rgb.max(axis=2) < 24


def foreground_seed_mask(rgb: np.ndarray, keep_black: bool = False) -> np.ndarray:
    values = rgb.astype(np.int16)
    distance_from_white = 255 - values.min(axis=2)
    color_span = values.max(axis=2) - values.min(axis=2)
    white = near_white_mask(rgb)
    black = near_black_mask(rgb) if not keep_black else np.zeros(white.shape, dtype=bool)
    return (~white) & (~black) & ((distance_from_white > 11) | (color_span > 14))


def smooth_rows(active: np.ndarray, radius: int = 22) -> np.ndarray:
    kernel = np.ones(radius * 2 + 1, dtype=np.int16)
    return np.convolve(active.astype(np.int16), kernel, mode="same") > 0


def row_bands(mask: np.ndarray, min_y: int = 200) -> list[tuple[int, int]]:
    working = mask.copy()
    working[:min_y, :] = False
    projection = working.sum(axis=1)
    threshold = max(10, int(mask.shape[1] * 0.012))
    active = smooth_rows(projection > threshold)

    bands: list[tuple[int, int]] = []
    start: int | None = None
    for index, value in enumerate(active):
        if value and start is None:
            start = index
        elif not value and start is not None:
            end = index - 1
            if end - start >= 38:
                bands.append((start, end))
            start = None

    if start is not None and len(active) - start >= 38:
        bands.append((start, len(active) - 1))

    return bands


def fill_holes(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    blocked = mask
    visited = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def push(y: int, x: int) -> None:
        if y < 0 or y >= h or x < 0 or x >= w:
            return
        if visited[y, x] or blocked[y, x]:
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

    return (~visited) & (~blocked)


def make_alpha(rgb: np.ndarray, keep_black: bool = False) -> np.ndarray:
    seed = foreground_seed_mask(rgb, keep_black=keep_black)
    seed_image = Image.fromarray((seed.astype(np.uint8) * 255), mode="L")
    closed = seed_image.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    closed_mask = np.asarray(closed) > 0

    holes = fill_holes(closed_mask)

    values = rgb.astype(np.int16)
    distance = 255 - values.min(axis=2)
    color_span = values.max(axis=2) - values.min(axis=2)
    edge_strength = np.maximum(distance, color_span)
    soft_alpha = np.clip((edge_strength - 6) * 12, 0, 255).astype(np.uint8)
    soft_alpha[near_white_mask(rgb)] = 0
    if not keep_black:
        soft_alpha[near_black_mask(rgb)] = 0

    alpha = np.maximum(soft_alpha, (holes.astype(np.uint8) * 255))
    alpha[closed_mask] = np.maximum(alpha[closed_mask], 215)
    return alpha


def decontaminate_white_edges(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    corrected = rgb.astype(np.float32).copy()
    a = alpha.astype(np.float32) / 255.0
    partial = (alpha > 0) & (alpha < 245)
    safe_a = np.maximum(a, 0.05)
    for channel in range(3):
        corrected_channel = (corrected[:, :, channel] - (1.0 - safe_a) * 255.0) / safe_a
        corrected[:, :, channel] = np.where(partial, corrected_channel, corrected[:, :, channel])
    return np.clip(corrected, 0, 255).astype(np.uint8)


def content_bbox(alpha: np.ndarray, threshold: int = 8) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(alpha > threshold)
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


def is_plus_sign_candidate(global_bbox: tuple[int, int, int, int], row_index: int, col_index: int) -> bool:
    x1, y1, x2, y2 = global_bbox
    width = x2 - x1
    height = y2 - y1
    return row_index == 0 and col_index == 0 and width < 130 and height < 130 and y1 < 390


def save_rgba_crop(
    source_rgb: np.ndarray,
    bbox: tuple[int, int, int, int],
    output_path: Path,
    keep_black: bool = False,
) -> Image.Image:
    x1, y1, x2, y2 = bbox
    rgb = source_rgb[y1:y2, x1:x2, :]
    alpha = make_alpha(rgb, keep_black=keep_black)
    corrected_rgb = decontaminate_white_edges(rgb, alpha)
    rgba = np.dstack([corrected_rgb, alpha])
    image = Image.fromarray(rgba, mode="RGBA")
    image.save(output_path)
    return image


def checkerboard(size: tuple[int, int], tile: int = 12) -> Image.Image:
    w, h = size
    image = Image.new("RGB", size, "#f5f5f5")
    draw = ImageDraw.Draw(image)
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            if ((x // tile) + (y // tile)) % 2 == 0:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e7e7e7")
    return image


def make_preview(sticker_paths: list[Path], output_path: Path, columns: int = 4) -> None:
    thumb_size = 150
    label_height = 24
    gap = 18
    rows = math.ceil(len(sticker_paths) / columns)
    width = columns * thumb_size + (columns + 1) * gap
    height = rows * (thumb_size + label_height) + (rows + 1) * gap
    preview = checkerboard((width, height), tile=14)
    draw = ImageDraw.Draw(preview)

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    except Exception:
        font = ImageFont.load_default()

    for index, path in enumerate(sticker_paths):
        row = index // columns
        col = index % columns
        x = gap + col * (thumb_size + gap)
        y = gap + row * (thumb_size + label_height + gap)
        sticker = Image.open(path).convert("RGBA")
        sticker.thumbnail((thumb_size, thumb_size), Image.Resampling.LANCZOS)
        paste_x = x + (thumb_size - sticker.width) // 2
        paste_y = y + (thumb_size - sticker.height) // 2
        preview.paste(sticker, (paste_x, paste_y), sticker)
        label = path.stem
        draw.text((x, y + thumb_size + 5), label, fill="#333333", font=font)

    preview.save(output_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--padding", default=18, type=int)
    parser.add_argument("--columns", default=4, type=int)
    parser.add_argument("--min-y", default=200, type=int)
    parser.add_argument("--preview-columns", default=4, type=int)
    parser.add_argument("--keep-black", action="store_true")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    rgb = np.asarray(source)
    h, w = rgb.shape[:2]
    seed = foreground_seed_mask(rgb)
    bands = row_bands(seed, min_y=args.min_y)

    out_dir = args.out_dir
    sticker_dir = out_dir / "stickers"
    if sticker_dir.exists():
        shutil.rmtree(sticker_dir)
    sticker_dir.mkdir(parents=True, exist_ok=True)

    transparent_sheet = Image.new("RGBA", source.size, (255, 255, 255, 0))
    sticker_paths: list[Path] = []
    metadata: list[dict[str, object]] = []
    columns = args.columns
    sticker_index = 1

    for row_index, (band_y1, band_y2) in enumerate(bands):
        for col_index in range(columns):
            cell_x1 = int(round(col_index * w / columns))
            cell_x2 = int(round((col_index + 1) * w / columns))
            cell = seed[band_y1 : band_y2 + 1, cell_x1:cell_x2]
            bbox = content_bbox((cell.astype(np.uint8) * 255), threshold=1)
            if bbox is None:
                continue

            local_x1, local_y1, local_x2, local_y2 = bbox
            global_bbox = (
                cell_x1 + local_x1,
                band_y1 + local_y1,
                cell_x1 + local_x2,
                band_y1 + local_y2,
            )

            if is_plus_sign_candidate(global_bbox, row_index, col_index):
                continue

            gx1, gy1, gx2, gy2 = global_bbox
            if (gx2 - gx1) * (gy2 - gy1) < 1800:
                continue

            padded = pad_bbox(global_bbox, args.padding, w, h)
            name = f"sticker_{sticker_index:02d}.png"
            output_path = sticker_dir / name
            sticker = save_rgba_crop(rgb, padded, output_path, keep_black=args.keep_black)
            transparent_sheet.paste(sticker, (padded[0], padded[1]), sticker)

            sticker_paths.append(output_path)
            metadata.append(
                {
                    "file": str(output_path.name),
                    "row": row_index + 1,
                    "column": col_index + 1,
                    "bbox": padded,
                    "size": sticker.size,
                }
            )
            sticker_index += 1

    transparent_sheet_path = out_dir / "sticker_sheet_transparent.png"
    transparent_sheet.save(transparent_sheet_path)

    preview_path = out_dir / "sticker_cutout_preview.png"
    make_preview(sticker_paths, preview_path, columns=args.preview_columns)

    zip_base = out_dir / "sticker_cutouts"
    archive_path = shutil.make_archive(str(zip_base), "zip", root_dir=sticker_dir)

    metadata_path = out_dir / "sticker_cutouts_metadata.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps({
        "count": len(sticker_paths),
        "stickers_dir": str(sticker_dir),
        "preview": str(preview_path),
        "sheet": str(transparent_sheet_path),
        "zip": archive_path,
        "metadata": str(metadata_path),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
