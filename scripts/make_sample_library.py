#!/usr/bin/env python3
"""Generates a small, realistic-looking photo library for trying Relive in the iOS Simulator.

The simulator's Photos app ships with only a handful of undated sample images, which makes the
story trivially thin. This script writes ~80 JPEGs with capture dates and GPS coordinates that
exercise the Memory Engine:

  * evenings at home in Istanbul across six months (home detection, repeated place)
  * a four-day trip to Kaş with a day in Kekova (a trip chapter with a different place inside)
  * New Year's Eve without location (time-based naming, the after-midnight rule)
  * a burst of near-identical shots (collapsed behind "Show similar")
  * a WhatsApp-style resized copy saved days later without location (duplicate detection)
  * three scattered single photos in one month (gathered into "Moments from March")

Requirements: Pillow (`pip install pillow`) and exiftool (`brew install exiftool`).

Usage:
    python3 scripts/make_sample_library.py OUTPUT_DIR
    xcrun simctl addmedia booted OUTPUT_DIR/*.jpg
"""

import datetime as dt
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

KADIKOY = (40.9906, 29.0290)
MODA = (40.9807, 29.0263)
KAS = (36.2018, 29.6377)
KAS_HARBOUR = (36.1990, 29.6410)
KEKOVA = (36.1936, 29.8420)

WIDTH, HEIGHT = 1200, 1600


def scene(seed: int, palette: tuple, variation: float = 0.0) -> Image.Image:
    """A simple 'photo': sky gradient, horizon, sun, and a couple of figures."""
    rng = random.Random(seed)
    sky_top, sky_bottom, ground = palette
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    horizon = int(HEIGHT * (0.5 + rng.uniform(-0.08, 0.08)))
    for y in range(horizon):
        t = y / horizon
        color = tuple(int(a + (b - a) * t) for a, b in zip(sky_top, sky_bottom))
        draw.line([(0, y), (WIDTH, y)], fill=color)
    for y in range(horizon, HEIGHT):
        t = (y - horizon) / (HEIGHT - horizon)
        color = tuple(int(c * (1 - 0.35 * t)) for c in ground)
        draw.line([(0, y), (WIDTH, y)], fill=color)

    sun_x = int(WIDTH * (rng.uniform(0.15, 0.85) + variation))
    sun_y = int(horizon * rng.uniform(0.2, 0.6))
    radius = rng.randint(70, 140)
    draw.ellipse([sun_x - radius, sun_y - radius, sun_x + radius, sun_y + radius], fill=(255, 236, 190))

    for index in range(rng.randint(1, 3)):
        x = int(WIDTH * (0.25 + 0.25 * index + rng.uniform(-0.05, 0.05) + variation))
        top = horizon + rng.randint(-260, -120)
        draw.rounded_rectangle([x - 60, top, x + 60, top + 420], radius=50, fill=(40, 34, 30))
        draw.ellipse([x - 55, top - 120, x + 55, top - 10], fill=(60, 48, 40))

    for _ in range(rng.randint(8, 20)):
        x, y = rng.randint(0, WIDTH), rng.randint(horizon, HEIGHT)
        r = rng.randint(10, 60)
        shade = tuple(max(0, c - rng.randint(20, 60)) for c in ground)
        draw.ellipse([x - r, y - r // 2, x + r, y + r // 2], fill=shade)

    # Fine texture, as real photos have (grass, water, fabric, sensor noise).
    texture = Image.effect_noise((WIDTH, HEIGHT), 28).convert("RGB")
    image = Image.blend(image, texture, 0.12)
    return image.filter(ImageFilter.GaussianBlur(radius=1.2))


def add_noise(image: Image.Image, seed: int, amount: int = 6) -> Image.Image:
    rng = random.Random(seed)
    pixels = image.load()
    for _ in range(4000):
        x, y = rng.randrange(image.width), rng.randrange(image.height)
        r, g, b = pixels[x, y]
        delta = rng.randint(-amount, amount)
        pixels[x, y] = (max(0, min(255, r + delta)), max(0, min(255, g + delta)), max(0, min(255, b + delta)))
    return image


PALETTES = {
    "evening": ((38, 52, 92), (214, 132, 96), (70, 64, 72)),
    "sea": ((92, 160, 214), (190, 222, 240), (32, 104, 150)),
    "golden": ((120, 150, 200), (246, 196, 130), (120, 96, 70)),
    "night": ((12, 16, 36), (60, 50, 90), (30, 28, 40)),
    "spring": ((150, 200, 230), (230, 240, 250), (90, 150, 80)),
}


def main(output: Path) -> None:
    if not shutil.which("exiftool"):
        sys.exit("exiftool is required (brew install exiftool)")
    output.mkdir(parents=True, exist_ok=True)
    photos = []  # (filename, datetime, (lat, lon) | None)
    counter = 0

    def save(image: Image.Image, when: dt.datetime, where, name_hint: str, size=None) -> str:
        nonlocal counter
        counter += 1
        filename = f"{counter:03d}-{name_hint}.jpg"
        if size:
            image = image.resize(size)
        image.save(output / filename, "JPEG", quality=88)
        photos.append((filename, when, where))
        return filename

    # Evenings at home, January–June 2025.
    for month in range(1, 7):
        start = dt.datetime(2025, month, 12, 19, 5)
        for shot in range(6):
            when = start + dt.timedelta(minutes=shot * 7)
            where = MODA if shot % 2 else KADIKOY
            save(scene(month * 100 + shot, PALETTES["evening"]), when, where, f"home-{month}")

    # Kaş, August 6–9 2025, with Kekova on the 8th.
    trip = [
        (dt.datetime(2025, 8, 6, 18, 20), KAS, "golden", 7),
        (dt.datetime(2025, 8, 7, 10, 30), KAS, "sea", 9),
        (dt.datetime(2025, 8, 8, 9, 40), KEKOVA, "sea", 8),
        (dt.datetime(2025, 8, 9, 9, 15), KAS_HARBOUR, "golden", 6),
    ]
    trip_photos = []
    for day, (start, where, palette, count) in enumerate(trip):
        for shot in range(count):
            when = start + dt.timedelta(minutes=shot * 17)
            trip_photos.append(save(scene(5000 + day * 50 + shot, PALETTES[palette]), when, where, f"kas-{day + 1}"))

    # A burst of near-identical shots on the beach.
    burst_base = scene(7777, PALETTES["sea"])
    for shot in range(4):
        when = dt.datetime(2025, 8, 7, 12, 2, shot * 2)
        save(add_noise(burst_base.copy(), shot), when, KAS, "kas-burst")

    # A WhatsApp-style copy of a trip photo: smaller, no location, saved days later.
    original = Image.open(output / trip_photos[3]).convert("RGB")
    save(original, dt.datetime(2025, 8, 14, 21, 3), None, "whatsapp-copy", size=(600, 800))

    # New Year's Eve, no location.
    for shot, minutes in enumerate([0, 45, 80, 110, 130]):
        when = dt.datetime(2024, 12, 31, 22, 40) + dt.timedelta(minutes=minutes)
        save(scene(9000 + shot, PALETTES["night"]), when, None, "new-years-eve")

    # Scattered single photos in March 2025.
    for day in (3, 15, 27):
        save(scene(9500 + day, PALETTES["spring"]), dt.datetime(2025, 3, day, 13, 10), None, "march")

    # Write capture dates and GPS with exiftool (Photos reads these on import).
    for filename, when, where in photos:
        stamp = when.strftime("%Y:%m:%d %H:%M:%S")
        args = ["exiftool", "-q", "-overwrite_original", f"-DateTimeOriginal={stamp}", f"-CreateDate={stamp}"]
        if where:
            lat, lon = where
            args += [
                f"-GPSLatitude={abs(lat)}", f"-GPSLatitudeRef={'N' if lat >= 0 else 'S'}",
                f"-GPSLongitude={abs(lon)}", f"-GPSLongitudeRef={'E' if lon >= 0 else 'W'}",
            ]
        subprocess.run(args + [str(output / filename)], check=True)

    print(f"Wrote {len(photos)} photos to {output}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
