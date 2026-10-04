#!/usr/bin/env python3
"""Compare the running game's memory (through the DOSBox fork's API) with a save
file, to check what the real game made of it after you loaded it.

  python3 scripts/verify_loaded_save.py ~/DOS/MAGIC/SAVE9.GAM

Checks the wizard records, terrain, landmass, minerals, explored map and terrain
flags. Addresses are from docs/reference/live-ram-map.md (re-check them after a
fresh DOSBox launch). Exit status 0 when everything matches, 1 otherwise. Read
only: it never writes to the game.
"""
import sys, urllib.request

API = "http://127.0.0.1:8086/api/v1/memory/0x{:x}/{}"
W, H = 60, 40
# name, save offset, RAM address, bytes, tile width (bytes), planes of 2400 tiles
BLOCKS = [
    ("wizards", 0x09E8, 0x328BA, 5 * 0x4C8, 0, 0),
    ("terrain", 0x2698, 0x72630, 9600, 2, 2),
    ("landmass", 0x4D98, 0x74DC0, 4800, 1, 2),
    ("minerals", 0x13554, 0x760B0, 4800, 1, 2),
    ("explored", 0x14814, 0x78690, 4800, 1, 2),
    ("terrain_flags", 0x1CBB8, 0x773A0, 4800, 1, 2),
]


def ram(addr, size):
    with urllib.request.urlopen(API.format(addr, size), timeout=5) as r:
        return r.read()


def main(path):
    save = open(path, "rb").read()
    print(f"{path}: {len(save)} bytes")
    name = save[0x09E8 + 1:0x09E8 + 21].split(b"\0")[0].decode("latin1")
    live = ram(0x328BA, 0x4C8)[1:21].split(b"\0")[0].decode("latin1")
    print(f"wizard in file: {name!r}; wizard in the running game: {live!r}")
    ok = True
    for label, off, addr, size, width, planes in BLOCKS:
        want, got = save[off:off + size], ram(addr, size)
        if want == got:
            print(f"  {label:14s} identical ({size} bytes)")
            continue
        ok = False
        width = width or 1
        diffs = [i for i in range(0, size, width) if want[i:i + width] != got[i:i + width]]
        line = f"  {label:14s} DIFFERS in {len(diffs)} of {size // width} entries"
        if planes:
            cells = [(i // width // (W * H), (i // width) % (W * H) % W, (i // width) % (W * H) // W) for i in diffs[:8]]
            line += "; first (plane, x, y): " + ", ".join(f"({p},{x},{y})" for p, x, y in cells)
        print(line)
    print("RESULT:", "the game holds exactly what the file says" if ok else "the game differs from the file")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        sys.exit(main(sys.argv[1]))
    except OSError as e:
        sys.exit(f"cannot read the game's memory (is DOSBox running with the API on?): {e}")
