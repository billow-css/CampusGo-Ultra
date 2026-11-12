#!/usr/bin/env python3
"""Export the approved artwork to macOS icon sizes with the system image tools."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ROOT / "Design/AppIcon-source.png")
parser.add_argument("--output", type=Path, default=ROOT / "Resources/NUISTGo.icns")
args = parser.parse_args()
source = args.source.resolve(strict=True)
output = args.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="nuistgo-icon-") as temporary:
    iconset = Path(temporary) / "NUISTGo.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            suffix = "@2x" if scale == 2 else ""
            target = iconset / f"icon_{points}x{points}{suffix}.png"
            subprocess.run(["sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
                            str(source), "--out", str(target)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["iconutil", "--convert", "icns", "--output", str(output), str(iconset)], check=True)
print(output)
