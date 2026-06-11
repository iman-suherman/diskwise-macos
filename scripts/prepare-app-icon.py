#!/usr/bin/env python3
"""Prepare the DiskWise dock icon: remove black matte and fit to macOS safe area."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops


def remove_black_background(image: Image.Image, threshold: int = 35) -> Image.Image:
    """Turn near-black pixels transparent while preserving rounded edge anti-aliasing."""
    rgba = image.convert("RGBA")
    red, green, blue, alpha = rgba.split()
    luminance = Image.merge("RGB", (red, green, blue)).convert("L")
    content_mask = luminance.point(lambda value: 255 if value > threshold else 0)
    if alpha.getextrema()[0] < 255:
        content_mask = ImageChops.multiply(content_mask, alpha)
    rgba.putalpha(content_mask)
    return rgba


def trim_transparent_bounds(image: Image.Image, margin: int = 0) -> Image.Image:
    """Crop to visible content."""
    alpha = image.split()[3]
    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None:
        return image

    left, top, right, bottom = bbox
    left = max(0, left - margin)
    top = max(0, top - margin)
    right = min(image.width, right + margin)
    bottom = min(image.height, bottom + margin)
    return image.crop((left, top, right, bottom))


def fit_to_dock_canvas(
    image: Image.Image,
    size: int = 1024,
    padding_ratio: float = 0.08,
) -> Image.Image:
    """
    Center icon content on a transparent square canvas.

    macOS applies its own squircle mask in the Dock, so we keep ~8% inset to
    avoid clipping the artwork's rounded corners.
    """
    content_limit = int(size * (1 - (padding_ratio * 2)))
    content = image.copy()
    content.thumbnail((content_limit, content_limit), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_x = (size - content.width) // 2
    offset_y = (size - content.height) // 2
    canvas.paste(content, (offset_x, offset_y), content)
    return canvas


def prepare_icon(
    source_path: Path,
    output_path: Path,
    *,
    size: int = 1024,
    threshold: int = 35,
    padding_ratio: float = 0.08,
    fit_canvas: bool = False,
) -> None:
    source = Image.open(source_path)
    cleaned = remove_black_background(source, threshold=threshold)
    prepared = trim_transparent_bounds(cleaned, margin=0)
    if fit_canvas:
        prepared = fit_to_dock_canvas(
            prepared,
            size=size,
            padding_ratio=padding_ratio,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    prepared.save(output_path, format="PNG", optimize=True)
    print(
        f"Prepared icon: {source_path.name} ({source.size[0]}x{source.size[1]}) "
        f"-> {output_path.name} ({prepared.size[0]}x{prepared.size[1]})"
    )


def resolve_source(assets_dir: Path, explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit

    raw = assets_dir / "AppIconSource.raw.png"
    uploaded = assets_dir / "AppIconSource.png"

    if raw.exists() and uploaded.exists() and uploaded.stat().st_mtime > raw.stat().st_mtime:
        return uploaded
    if raw.exists():
        return raw
    if uploaded.exists():
        return uploaded
    raise SystemExit(f"No icon source found in {assets_dir}")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    assets_dir = repo_root / "app" / "DiskWise" / "Assets"

    parser = argparse.ArgumentParser(description="Prepare DiskWise dock icon artwork.")
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="Master icon (defaults to newest of AppIconSource.raw.png / AppIconSource.png)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=assets_dir / "AppIconSource.png",
        help="Prepared icon used by the Swift icon generator",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--threshold", type=int, default=35)
    parser.add_argument("--padding-ratio", type=float, default=0.08)
    parser.add_argument(
        "--fit-canvas",
        action="store_true",
        help="Center on a square canvas with macOS dock safe-area inset (default: crop to content)",
    )
    args = parser.parse_args()

    source_path = resolve_source(assets_dir, args.source)
    if not source_path.exists():
        raise SystemExit(f"Source icon not found: {source_path}")

    prepare_icon(
        source_path,
        args.output,
        size=args.size,
        threshold=args.threshold,
        padding_ratio=args.padding_ratio,
        fit_canvas=args.fit_canvas,
    )


if __name__ == "__main__":
    main()
