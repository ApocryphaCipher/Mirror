#!/usr/bin/env python3
"""Watch the running game's map blocks and print what changes, as it happens:
terrain (u16), minerals, explored and terrain flags (u8), through the DOSBox
fork's API. For seeing what a spell or action does to the map (docs/reference/
live-ram-map.md has the addresses; re-check them after a fresh DOSBox launch).

  python3 -u scripts/block_watch.py          # runs until Ctrl-C

A change of more than --max-list tiles in a block is summarised (a game load
looks like that), anything smaller is listed tile by tile as `plane x y old->new`.
"""
import argparse, struct, sys, time, urllib.request

API = "http://127.0.0.1:8086/api/v1/memory/0x{:x}/{}"
# name, RAM address, bytes per tile
BLOCKS = [
    ("terrain", 0x72630, 2),
    ("minerals", 0x760B0, 1),
    ("explored", 0x78690, 1),
    ("terrain_flags", 0x773A0, 1),
]
W, PLANE = 60, 2400


def read(addr, size):
    with urllib.request.urlopen(API.format(addr, size), timeout=3) as r:
        return r.read()


def tiles(raw, width):
    return struct.unpack("<%d%s" % (len(raw) // width, "H" if width == 2 else "B"), raw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=float, default=1.0)
    ap.add_argument("--max-list", type=int, default=60)
    args = ap.parse_args()
    prev = {}
    print("watching terrain, minerals, explored, terrain_flags; Ctrl-C to stop", flush=True)
    while True:
        try:
            cur = {name: tiles(read(addr, 2 * 2 * PLANE if width == 2 else 2 * PLANE), width)
                   for name, addr, width in BLOCKS}
        except Exception as e:
            print("API not reachable:", e, flush=True)
            time.sleep(5)
            continue
        for name, _, _ in BLOCKS:
            if name in prev and prev[name] != cur[name]:
                diff = [(i, a, b) for i, (a, b) in enumerate(zip(prev[name], cur[name])) if a != b]
                head = f"{name}: {len(diff)} tiles changed"
                if len(diff) > args.max_list:
                    planes = {p: sum(1 for i, _, _ in diff if i // PLANE == p) for p in (0, 1)}
                    print(f"{head} (too many to list; arcanus {planes[0]}, myrror {planes[1]}) "
                          f"e.g. {diff[0][1]}->{diff[0][2]}", flush=True)
                else:
                    cells = "; ".join(f"p{i // PLANE} x{(i % PLANE) % W} y{(i % PLANE) // W} {a}->{b}"
                                      for i, a, b in diff)
                    print(f"{head}: {cells}", flush=True)
        prev = cur
        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
