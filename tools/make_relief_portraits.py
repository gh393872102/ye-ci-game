"""Rebuild the cropped 3:2 recruitment portraits from the 32 original P8 paintings."""
from pathlib import Path
from PIL import Image

folder = Path(__file__).resolve().parents[1] / "assets/portraits/p8"
tile_width, tile_height = 192, 128
sheet = Image.new("RGB", (8 * tile_width, 4 * tile_height))
for index in range(32):
    with Image.open(folder / f"H{index + 1:02d}.png") as original:
        height = min(original.height, round(original.width * tile_height / tile_width))
        bust = original.crop((0, 0, original.width, height))
        tile = bust.convert("RGB").resize((tile_width, tile_height), Image.Resampling.LANCZOS)
        sheet.paste(tile, ((index % 8) * tile_width, (index // 8) * tile_height))
sheet.save(folder / "relief-busts.webp", quality=86, method=6)
