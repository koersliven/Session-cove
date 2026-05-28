#!/usr/bin/env python3
"""Clean mascot PNG backgrounds - flood-fill from edges to make background transparent.
Handles both light AND dark checker patterns. Uses only PIL."""

import sys
from PIL import Image


def is_bg_color(r, g, b, a):
    """Check if a pixel looks like checker/gray/white background."""
    if a < 20:
        return True
    ri, gi, bi = int(r), int(g), int(b)
    is_neutral = abs(ri - gi) < 18 and abs(gi - bi) < 18
    # Near-black (one side of dark checker)
    if is_neutral and ri < 15:
        return True
    # Dark grays (dark checker pattern: RGB 30-115)
    if abs(ri - gi) < 14 and abs(gi - bi) < 14 and 25 < ri < 120:
        return True
    # Light grays and whites (standard checker)
    if is_neutral and ri > 100:
        return True
    return False


def flood_fill_edges(img):
    """Flood fill from edges marking background pixels."""
    w, h = img.size
    pixels = img.load()
    to_clear = set()
    visited = set()

    seeds = []
    for x in range(w):
        seeds.append((x, 0))
        seeds.append((x, h - 1))
    for y in range(h):
        seeds.append((0, y))
        seeds.append((w - 1, y))

    queue = []
    for x, y in seeds:
        if (x, y) not in visited:
            r, g, b, a = pixels[x, y]
            if is_bg_color(r, g, b, a):
                visited.add((x, y))
                to_clear.add((x, y))
                queue.append((x, y))

    idx = 0
    while idx < len(queue):
        cx, cy = queue[idx]
        idx += 1
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                visited.add((nx, ny))
                r, g, b, a = pixels[nx, ny]
                if is_bg_color(r, g, b, a):
                    to_clear.add((nx, ny))
                    queue.append((nx, ny))

    return to_clear


def clean_isolated_checker(img, cleared):
    """Remove isolated dark/light pixels surrounded by transparency (remnant checker)."""
    w, h = img.size
    pixels = img.load()
    extra_clear = set()

    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if (x, y) in cleared or (x, y) in extra_clear:
                continue
            r, g, b, a = pixels[x, y]
            if a < 20:
                continue
            # Count transparent neighbors
            transparent_neighbors = 0
            total_neighbors = 0
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        total_neighbors += 1
                        if (nx, ny) in cleared or pixels[nx, ny][3] < 20:
                            transparent_neighbors += 1
            # If mostly surrounded by transparent, this is remnant checker
            if total_neighbors > 0 and transparent_neighbors / total_neighbors > 0.6:
                ri, gi, bi = int(r), int(g), int(b)
                if abs(ri - gi) < 20 and abs(gi - bi) < 20:
                    extra_clear.add((x, y))

    return extra_clear


def clean_halo(img, cleared):
    """Remove white/gray halo pixels adjacent to cleared background."""
    w, h = img.size
    pixels = img.load()
    halo = set()

    for cx, cy in cleared:
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in cleared and (nx, ny) not in halo:
                r, g, b, a = pixels[nx, ny]
                if int(a) > 30:
                    avg = (int(r) + int(g) + int(b)) / 3
                    if avg > 140 and abs(int(r) - int(g)) < 25 and abs(int(g) - int(b)) < 25:
                        halo.add((nx, ny))

    return halo


def process_image(input_path, output_path):
    """Process a single mascot image."""
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size
    pixels = img.load()

    print(f"Processing {input_path} ({w}x{h})")

    cleared = flood_fill_edges(img)
    print(f"  Flood-fill: {len(cleared)} pixels ({100*len(cleared)//(w*h)}%)")

    isolated = clean_isolated_checker(img, cleared)
    print(f"  Isolated checker: {len(isolated)} pixels")

    all_cleared = cleared | isolated
    halo = clean_halo(img, all_cleared)
    print(f"  Halo: {len(halo)} pixels")

    for x, y in all_cleared:
        pixels[x, y] = (0, 0, 0, 0)
    for x, y in halo:
        pixels[x, y] = (0, 0, 0, 0)

    img.save(output_path, optimize=True)

    corner_alphas = [pixels[0, 0][3], pixels[w-1, 0][3], pixels[0, h-1][3], pixels[w-1, h-1][3]]
    print(f"  Corners: {corner_alphas}")
    print(f"  Saved: {output_path}")
    print()


if __name__ == "__main__":
    import glob

    if len(sys.argv) < 2:
        print("Usage: python clean_mascot_alpha.py <input.png> [output.png]")
        print("       python clean_mascot_alpha.py --batch <dir>")
        sys.exit(1)

    if sys.argv[1] == "--batch":
        directory = sys.argv[2] if len(sys.argv) > 2 else "SessionCove/Resources"
        for path in sorted(glob.glob(f"{directory}/claude_*.png")):
            process_image(path, path)
    else:
        input_path = sys.argv[1]
        output_path = sys.argv[2] if len(sys.argv) > 2 else input_path
        process_image(input_path, output_path)
