#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def light_background_mask(rgb: np.ndarray, min_light: int = 220, max_span: int = 45) -> np.ndarray:
    values = rgb.astype(np.int16)
    span = values.max(axis=2) - values.min(axis=2)
    return (values.min(axis=2) >= min_light) & (span <= max_span)


def fill_holes(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    visited = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def push(y: int, x: int) -> None:
        if y < 0 or y >= h or x < 0 or x >= w:
            return
        if visited[y, x] or mask[y, x]:
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

    return (~visited) & (~mask)


def trim_black_frame(rgb: np.ndarray) -> tuple[np.ndarray, tuple[int, int]]:
    black = rgb.max(axis=2) < 18
    h, w = black.shape
    top = 0
    bottom = h

    while top < bottom and black[top].mean() > 0.92:
        top += 1
    while bottom > top and black[bottom - 1].mean() > 0.92:
        bottom -= 1

    return rgb[top:bottom, :, :], (top, bottom)


def content_bbox(mask: np.ndarray, threshold: int = 1) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask > threshold)
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


def background_color(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    if bg.any():
        return np.median(rgb[bg], axis=0).astype(np.float32)
    return np.array([255, 255, 255], dtype=np.float32)


def make_alpha(
    rgb: np.ndarray,
    min_light: int = 220,
    max_span: int = 45,
    close_size: int = 11,
) -> tuple[np.ndarray, np.ndarray]:
    bg = light_background_mask(rgb, min_light=min_light, max_span=max_span)
    seed = ~bg
    bg_rgb = background_color(rgb, bg)
    brightness = rgb.astype(np.float32).mean(axis=2)

    close_size = max(3, close_size | 1)
    seed_image = Image.fromarray((seed.astype(np.uint8) * 255), mode="L")
    close_mask = np.asarray(seed_image.filter(ImageFilter.MaxFilter(close_size))) > 0
    support_size = min(61, max(close_size + 14, 25) | 1)
    light_support = np.asarray(seed_image.filter(ImageFilter.MaxFilter(support_size))) > 0
    light_subject = bg & light_support & ((brightness - float(bg_rgb.mean())) >= 5.0)
    holes = fill_holes(close_mask)

    distance = np.max(np.abs(rgb.astype(np.float32) - bg_rgb), axis=2)
    soft_alpha = np.clip((distance - 6) * 9, 0, 255).astype(np.uint8)
    soft_alpha[bg & ~(holes | light_subject)] = 0

    alpha = np.maximum(soft_alpha, (holes | light_subject).astype(np.uint8) * 255)
    alpha[seed] = np.maximum(alpha[seed], 235)
    return alpha, bg_rgb


def decontaminate_edges(rgb: np.ndarray, alpha: np.ndarray, bg_rgb: np.ndarray) -> np.ndarray:
    corrected = rgb.astype(np.float32).copy()
    a = alpha.astype(np.float32) / 255.0
    partial = (alpha > 0) & (alpha < 245)
    safe_a = np.maximum(a, 0.05)
    for channel in range(3):
        channel_values = (corrected[:, :, channel] - (1.0 - safe_a) * bg_rgb[channel]) / safe_a
        corrected[:, :, channel] = np.where(partial, channel_values, corrected[:, :, channel])
    return np.clip(corrected, 0, 255).astype(np.uint8)


def save_cutout(
    source_rgb: np.ndarray,
    bbox: tuple[int, int, int, int],
    output_path: Path,
    min_light: int = 220,
    max_span: int = 45,
    close_size: int = 11,
) -> Image.Image:
    x1, y1, x2, y2 = bbox
    rgb = source_rgb[y1:y2, x1:x2, :]
    alpha, bg_rgb = make_alpha(rgb, min_light=min_light, max_span=max_span, close_size=close_size)
    corrected = decontaminate_edges(rgb, alpha, bg_rgb)
    image = Image.fromarray(np.dstack([corrected, alpha]), mode="RGBA")
    image.save(output_path)
    return image


def detect_row_bands(seed: np.ndarray, min_y: int, max_y: int, min_height: int = 50) -> list[tuple[int, int]]:
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
            if end - start >= min_height:
                bands.append((start, end))
            start = None
    if start is not None and len(closed) - start >= min_height:
        bands.append((start, len(closed) - 1))
    return bands


def checkerboard(size: tuple[int, int], tile: int = 14) -> Image.Image:
    image = Image.new("RGB", size, "#f5f5f5")
    draw = ImageDraw.Draw(image)
    w, h = size
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            if ((x // tile) + (y // tile)) % 2 == 0:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e7e7e7")
    return image


def make_preview(sticker_paths: list[Path], output_path: Path, columns: int = 5) -> None:
    thumb = 150
    label_h = 24
    gap = 18
    rows = math.ceil(len(sticker_paths) / columns)
    width = columns * thumb + (columns + 1) * gap
    height = rows * (thumb + label_h) + (rows + 1) * gap
    preview = checkerboard((width, height))
    draw = ImageDraw.Draw(preview)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    except Exception:
        font = ImageFont.load_default()

    for index, path in enumerate(sticker_paths):
        row = index // columns
        col = index % columns
        x = gap + col * (thumb + gap)
        y = gap + row * (thumb + label_h + gap)
        sticker = Image.open(path).convert("RGBA")
        sticker.thumbnail((thumb, thumb), Image.Resampling.LANCZOS)
        preview.paste(sticker, (x + (thumb - sticker.width) // 2, y + (thumb - sticker.height) // 2), sticker)
        draw.text((x, y + thumb + 5), path.stem, fill="#333333", font=font)
    preview.save(output_path)


def cut_grid(args: argparse.Namespace) -> dict[str, object]:
    source = Image.open(args.input).convert("RGB")
    rgb = np.asarray(source)
    h, w = rgb.shape[:2]
    bg = light_background_mask(rgb, min_light=args.min_light, max_span=args.max_span)
    seed = ~bg
    bands = detect_row_bands(seed, min_y=args.min_y, max_y=args.max_y)

    out_dir = args.out_dir
    stickers_dir = out_dir / "stickers"
    if stickers_dir.exists():
        shutil.rmtree(stickers_dir)
    stickers_dir.mkdir(parents=True, exist_ok=True)

    transparent_sheet = Image.new("RGBA", source.size, (255, 255, 255, 0))
    paths: list[Path] = []
    metadata: list[dict[str, object]] = []
    index = 1
    skip_cells = set(args.skip_cell or [])

    for row_index, (band_y1, band_y2) in enumerate(bands, start=1):
        for col_index in range(1, args.columns + 1):
            if f"{row_index},{col_index}" in skip_cells:
                continue

            cell_x1 = int(round((col_index - 1) * w / args.columns))
            cell_x2 = int(round(col_index * w / args.columns))
            cell = seed[band_y1:band_y2 + 1, cell_x1:cell_x2]
            bbox = content_bbox(cell.astype(np.uint8), threshold=0)
            if bbox is None:
                continue

            lx1, ly1, lx2, ly2 = bbox
            global_bbox = (cell_x1 + lx1, band_y1 + ly1, cell_x1 + lx2, band_y1 + ly2)
            gx1, gy1, gx2, gy2 = global_bbox
            if (gx2 - gx1) * (gy2 - gy1) < args.min_area:
                continue

            padded = pad_bbox(global_bbox, args.padding, w, h)
            output = stickers_dir / f"sticker_{index:02d}.png"
            sticker = save_cutout(rgb, padded, output, min_light=args.min_light, max_span=args.max_span, close_size=args.close_size)
            transparent_sheet.paste(sticker, (padded[0], padded[1]), sticker)
            paths.append(output)
            metadata.append({"file": output.name, "row": row_index, "column": col_index, "bbox": padded, "size": sticker.size})
            index += 1

    preview = out_dir / "sticker_cutout_preview.png"
    make_preview(paths, preview, columns=args.preview_columns)
    sheet = out_dir / "sticker_sheet_transparent.png"
    transparent_sheet.save(sheet)
    archive = shutil.make_archive(str(out_dir / "sticker_cutouts"), "zip", root_dir=stickers_dir)
    metadata_path = out_dir / "sticker_cutouts_metadata.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"count": len(paths), "stickers_dir": str(stickers_dir), "preview": str(preview), "sheet": str(sheet), "zip": archive, "metadata": str(metadata_path)}


def cut_single(args: argparse.Namespace) -> dict[str, object]:
    source = Image.open(args.input).convert("RGB")
    rgb, (offset_y, _) = trim_black_frame(np.asarray(source))
    bg = light_background_mask(rgb, min_light=args.min_light, max_span=args.max_span)
    seed = ~bg
    bbox = content_bbox(seed.astype(np.uint8), threshold=0)
    if bbox is None:
        raise SystemExit("No foreground found")

    padded = pad_bbox(bbox, args.padding, rgb.shape[1], rgb.shape[0])
    args.out_dir.mkdir(parents=True, exist_ok=True)
    output = args.out_dir / args.output_name
    image = save_cutout(rgb, padded, output, min_light=args.min_light, max_span=args.max_span, close_size=args.close_size)
    return {"file": str(output), "size": image.size, "source_trim_y": offset_y}


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="mode", required=True)

    grid = subparsers.add_parser("grid")
    grid.add_argument("--input", required=True, type=Path)
    grid.add_argument("--out-dir", required=True, type=Path)
    grid.add_argument("--columns", default=5, type=int)
    grid.add_argument("--preview-columns", default=5, type=int)
    grid.add_argument("--min-y", default=0, type=int)
    grid.add_argument("--max-y", default=10**9, type=int)
    grid.add_argument("--padding", default=20, type=int)
    grid.add_argument("--min-light", default=220, type=int)
    grid.add_argument("--max-span", default=45, type=int)
    grid.add_argument("--close-size", default=11, type=int)
    grid.add_argument("--min-area", default=1800, type=int)
    grid.add_argument("--skip-cell", action="append")

    single = subparsers.add_parser("single")
    single.add_argument("--input", required=True, type=Path)
    single.add_argument("--out-dir", required=True, type=Path)
    single.add_argument("--output-name", default="cutout.png")
    single.add_argument("--padding", default=18, type=int)
    single.add_argument("--min-light", default=220, type=int)
    single.add_argument("--max-span", default=45, type=int)
    single.add_argument("--close-size", default=11, type=int)

    args = parser.parse_args()
    result = cut_grid(args) if args.mode == "grid" else cut_single(args)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
