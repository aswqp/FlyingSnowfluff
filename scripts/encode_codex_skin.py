"""Lossless format conversion only; preserve sRGB and transparent RGB exactly."""
import sys
from PIL import Image

source, target = sys.argv[1:]
with Image.open(source) as image:
    assert image.mode == "RGBA" and image.size == (1536, 1872)
    profile = image.info["icc_profile"]
    image.save(target, format="WEBP", lossless=True, quality=100, method=6,
               exact=True, icc_profile=profile)
with Image.open(source) as before, Image.open(target) as after:
    assert before.tobytes() == after.tobytes(), "WebP encoding changed pixels"
    assert before.info["icc_profile"] == after.info["icc_profile"]
print("PASS: exact RGBA and sRGB preserved in WebP")
