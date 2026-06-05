#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


SOURCES = [
    (
        Path("/Users/xiuluo/Library/Application Support/LarkShell/sdk_storage/063286b6def05ac6f244916fa252e334/resources/images/img_v3_0212c_8212db31-b26c-45ed-9176-4378e0c7feeg.jpg"),
        [
            "mametchi", "weeptchi", "hypertchi", "kuchipatchi", "shykutchi",
            "bigsmile", "kikitchi", "shimagurutchi", "gozarutchi", "milktchi",
            "mimitchi", "picochutchi", "memetchi", "bubbletchi", "woopatchi",
            "neliatchi", "sebiretchi", "momotchi", "unimarutchi", "simasimatchi",
        ],
    ),
    (
        Path("/Users/xiuluo/Library/Application Support/LarkShell/sdk_storage/063286b6def05ac6f244916fa252e334/resources/images/img_v3_0212c_05eea38c-a417-438a-bd27-653b82f7e2ag.jpg"),
        [
            "yattachi", "nazotchi", "maidchi", "uwasatchi", "shirimotchi",
            "chukatchi", "watawatatchi", "crayontchi", "pierrotchi", "majokkotchi",
            "hatakemotchi", "butterflytchi", "attendant", "maskutchi", "ichirinshotchi",
            "nonopotchi", "himebaratchi", "pichipitchi", "youmotchi", "fairytchi",
        ],
    ),
    (
        Path("/Users/xiuluo/Library/Application Support/LarkShell/sdk_storage/063286b6def05ac6f244916fa252e334/resources/images/img_v3_0212c_6b9941d1-03bd-4108-9d56-cb9f6eeba7fg.jpg"),
        [
            "majoritchi", "madamchi", "lovesolatchi", "miraitchi", "clulutchi",
            "morijikatchi", "guriguritchi", "sunopotchi", "rinkurutchi", "oyajitchi",
            "charatchi", "nijanyatchi", "paintotchi", "rosetchi", "yotsubatchi",
            "hanafuwatchi", "mushiharutchi", "acchitchi", "tokonatchi", "tropicatchi",
        ],
    ),
    (
        Path("/Users/xiuluo/Library/Application Support/LarkShell/sdk_storage/063286b6def05ac6f244916fa252e334/resources/images/img_v3_0212c_be171b0a-596a-4cad-b298-cc5586e41f9g.jpg"),
        [
            "yashiharotchi", "decotchi", "young_dorotchi", "witching", "pumpkitchi",
            "amiamitchi", "santaclautchi", "akahanatchi", "yukipatchi", "flowertchi",
            "chamametchi", "shinshitchi", "bushinosuketchi", "marutchi", "orenetchi",
            "neenetchi", "himespetchi", "himetchi", "kyawatchi", "motetchi",
        ],
    ),
]

ROW_WINDOWS = [
    (725, 945),
    (1010, 1228),
    (1315, 1518),
    (1610, 1770),
]
COLUMNS = 5


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


def estimate_background(rgb: np.ndarray) -> np.ndarray:
    h, w = rgb.shape[:2]
    edge = 12
    border = np.concatenate(
        [
            rgb[:edge, :, :].reshape(-1, 3),
            rgb[h - edge :, :, :].reshape(-1, 3),
            rgb[:, :edge, :].reshape(-1, 3),
            rgb[:, w - edge :, :].reshape(-1, 3),
        ],
        axis=0,
    )
    values = border.astype(np.int16)
    span = values.max(axis=1) - values.min(axis=1)
    light = values.min(axis=1) > 205
    if np.count_nonzero(light & (span < 42)) > 50:
        border = border[light & (span < 42)]
    return np.median(border, axis=0).astype(np.float32)


def estimate_page_background(rgb: np.ndarray) -> np.ndarray:
    content = rgb[475:1870, :, :].reshape(-1, 3).astype(np.int16)
    span = content.max(axis=1) - content.min(axis=1)
    cream = (
        (content[:, 0] > 235)
        & (content[:, 1] > 225)
        & (content[:, 2] > 200)
        & (span < 65)
    )
    if np.count_nonzero(cream) < 100:
        return np.array([253, 248, 229], dtype=np.float32)
    return np.median(content[cream], axis=0).astype(np.float32)


def foreground_masks(rgb: np.ndarray, bg_rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    values = rgb.astype(np.float32)
    span = values.max(axis=2) - values.min(axis=2)
    diff = np.max(np.abs(values - bg_rgb), axis=2)
    brightness_delta = values.mean(axis=2) - float(bg_rgb.mean())

    dark_line = (values.min(axis=2) < 185) & (diff > 18)
    colorful = (span > 34) & (diff > 18)
    contrast = diff > 30
    bright_white = (brightness_delta > 13) & (diff > 20) & (values.min(axis=2) > 210)

    seed = dark_line | colorful | contrast | bright_white
    seed = np.asarray(
        Image.fromarray((seed.astype(np.uint8) * 255), mode="L")
        .filter(ImageFilter.MaxFilter(3))
        .filter(ImageFilter.MinFilter(3))
    ) > 0
    support = np.asarray(
        Image.fromarray((seed.astype(np.uint8) * 255), mode="L").filter(ImageFilter.MaxFilter(17))
    ) > 0
    closed_for_holes = np.asarray(
        Image.fromarray((seed.astype(np.uint8) * 255), mode="L").filter(ImageFilter.MaxFilter(5))
    ) > 0
    holes = fill_holes(closed_for_holes)
    alpha_region = seed | holes | (bright_white & support)
    return seed, support, holes, alpha_region


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

            area = len(xs)
            if area >= 220:
                continue
            y_index = np.asarray(ys)
            x_index = np.asarray(xs)
            values = rgb[y_index, x_index, :].astype(np.float32)
            channel_span = values.max(axis=1) - values.min(axis=1)
            mean_rgb = values.mean(axis=0)
            mean_span = float(channel_span.mean())
            pale_yellow = (
                mean_rgb[0] > 238
                and mean_rgb[1] > 232
                and 185 < mean_rgb[2] < 238
                and mean_span > 24
            )
            pale_gray = (
                area < 90
                and mean_rgb.min() > 205
                and mean_rgb[2] < 238
                and mean_span < 26
            )
            if pale_yellow or pale_gray:
                cleaned[y_index, x_index] = 0
    return cleaned


def make_cutout(rgb: np.ndarray, bg_rgb: np.ndarray | None = None) -> Image.Image:
    if bg_rgb is None:
        bg_rgb = estimate_background(rgb)
    seed, _support, holes, alpha_region = foreground_masks(rgb, bg_rgb)

    values = rgb.astype(np.float32)
    span = values.max(axis=2) - values.min(axis=2)
    diff = np.max(np.abs(values - bg_rgb), axis=2)
    edge_strength = np.maximum(diff, span * 0.85)
    soft_alpha = np.clip((edge_strength - 10.0) * 10.5, 0, 255).astype(np.uint8)
    soft_alpha[~alpha_region] = 0

    alpha = soft_alpha
    alpha[seed] = np.maximum(alpha[seed], 235)
    alpha[holes] = 255
    background_like = (diff < 20.0) & (span < 24.0)
    alpha[background_like] = 0
    alpha = remove_small_pale_artifacts(alpha, rgb)

    corrected = rgb.astype(np.float32).copy()
    partial = (alpha > 0) & (alpha < 245)
    a = np.maximum(alpha.astype(np.float32) / 255.0, 0.05)
    for channel in range(3):
        channel_values = (corrected[:, :, channel] - (1.0 - a) * bg_rgb[channel]) / a
        corrected[:, :, channel] = np.where(partial, channel_values, corrected[:, :, channel])

    rgba = np.dstack([np.clip(corrected, 0, 255).astype(np.uint8), alpha])
    return Image.fromarray(rgba, mode="RGBA")


def checkerboard(size: tuple[int, int], tile: int = 14) -> Image.Image:
    image = Image.new("RGB", size, "#f5f5f5")
    draw = ImageDraw.Draw(image)
    w, h = size
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            if ((x // tile) + (y // tile)) % 2 == 0:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill="#e6e6e6")
    return image


def make_preview(paths: list[Path], output_path: Path, columns: int = 8, solid: bool = False) -> None:
    thumb = 128
    label_h = 22
    gap = 14
    rows = math.ceil(len(paths) / columns)
    width = columns * thumb + (columns + 1) * gap
    height = rows * (thumb + label_h) + (rows + 1) * gap
    preview = Image.new("RGB", (width, height), "#9fd0ff") if solid else checkerboard((width, height))
    draw = ImageDraw.Draw(preview)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
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
        draw.text((x, y + thumb + 4), path.stem[:18], fill="#111111" if solid else "#333333", font=font)
    preview.save(output_path)


def make_transparent_contact_sheet(paths: list[Path], output_path: Path, columns: int = 10) -> None:
    cell = 180
    rows = math.ceil(len(paths) / columns)
    sheet = Image.new("RGBA", (columns * cell, rows * cell), (255, 255, 255, 0))
    for index, path in enumerate(paths):
        sticker = Image.open(path).convert("RGBA")
        sticker.thumbnail((cell - 28, cell - 28), Image.Resampling.LANCZOS)
        x = (index % columns) * cell + (cell - sticker.width) // 2
        y = (index // columns) * cell + (cell - sticker.height) // 2
        sheet.paste(sticker, (x, y), sticker)
    sheet.save(output_path)


def main() -> None:
    out_dir = Path("outputs/tamagotchi_cutouts")
    stickers_dir = out_dir / "stickers"
    if stickers_dir.exists():
        shutil.rmtree(stickers_dir)
    stickers_dir.mkdir(parents=True, exist_ok=True)

    paths: list[Path] = []
    metadata: list[dict[str, object]] = []
    index = 1
    for page_number, (source_path, names) in enumerate(SOURCES, start=1):
        source = Image.open(source_path).convert("RGB")
        rgb = np.asarray(source)
        page_bg_rgb = estimate_page_background(rgb)
        height, width = rgb.shape[:2]
        for row_index, (y1, y2) in enumerate(ROW_WINDOWS):
            for col_index in range(COLUMNS):
                name = names[row_index * COLUMNS + col_index]
                cell_x1 = int(round(col_index * width / COLUMNS))
                cell_x2 = int(round((col_index + 1) * width / COLUMNS))
                cell_rgb = rgb[y1:y2, cell_x1:cell_x2, :]
                bg_rgb = page_bg_rgb
                seed, _support, holes, alpha_region = foreground_masks(cell_rgb, bg_rgb)
                bbox = content_bbox(seed | holes | alpha_region)
                if bbox is None:
                    continue
                bbox = pad_bbox(bbox, 18, cell_x2 - cell_x1, y2 - y1)
                local_x1, local_y1, local_x2, local_y2 = bbox
                crop = rgb[y1 + local_y1 : y1 + local_y2, cell_x1 + local_x1 : cell_x1 + local_x2, :]
                image = make_cutout(crop, bg_rgb=bg_rgb)

                file_name = f"{index:02d}_p{page_number}_{name}.png"
                output = stickers_dir / file_name
                image.save(output)
                paths.append(output)
                metadata.append(
                    {
                        "file": file_name,
                        "page": page_number,
                        "row": row_index + 1,
                        "column": col_index + 1,
                        "name": name,
                        "bbox": [
                            cell_x1 + local_x1,
                            y1 + local_y1,
                            cell_x1 + local_x2,
                            y1 + local_y2,
                        ],
                        "size": image.size,
                    }
                )
                index += 1

    make_preview(paths, out_dir / "sticker_cutout_preview.png", columns=8, solid=False)
    make_preview(paths, out_dir / "sticker_cutout_preview_solid.png", columns=8, solid=True)
    make_transparent_contact_sheet(paths, out_dir / "sticker_sheet_transparent.png", columns=10)
    archive = shutil.make_archive(str(out_dir / "sticker_cutouts"), "zip", root_dir=stickers_dir)
    (out_dir / "sticker_cutouts_metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(
        {
            "count": len(paths),
            "stickers_dir": str(stickers_dir),
            "preview": str(out_dir / "sticker_cutout_preview.png"),
            "solid_preview": str(out_dir / "sticker_cutout_preview_solid.png"),
            "sheet": str(out_dir / "sticker_sheet_transparent.png"),
            "zip": archive,
            "metadata": str(out_dir / "sticker_cutouts_metadata.json"),
        },
        ensure_ascii=False,
        indent=2,
    ))


if __name__ == "__main__":
    main()
