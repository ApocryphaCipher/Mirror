#!/usr/bin/env python3
"""Watch the running game's terrain block through the DOSBox fork's API and log
every new map it sees, so a play session can hunt for rare tile numbers without
a message per map (STORY-007: which tiles are the animated ones).

  python3 scripts/terrain_watch.py            # runs until Ctrl-C
  python3 scripts/terrain_watch.py --targets 18,33,179 --no-checkpoint

Polls the 2 x 2400 u16 terrain block (RAM 0x72630, docs/reference/live-ram-map.md;
re-check the address after a fresh DOSBox launch). A map counts once its bytes
have been identical for two polls. Each is appended to
~/.mirror/dev/DOSbox/terrain-watch.jsonl with its counts of the target tiles and,
when a target shows up, a `gama checkpoint` is taken so the dump and screenshot
are kept in the Evi vault.
"""
import argparse, collections, hashlib, json, os, struct, subprocess, sys, time, urllib.request

API = "http://127.0.0.1:8086/api/v1/memory/0x72630/9600"
LOG = os.path.expanduser("~/.mirror/dev/DOSbox/terrain-watch.jsonl")
HERE = os.path.dirname(os.path.abspath(__file__))


def read_terrain():
    with urllib.request.urlopen(API, timeout=3) as r:
        data = r.read()
    return struct.unpack("<4800H", data), data


def looks_like_a_map(t):
    # A generated map is mostly ocean (0/601) with some land, all tiles below
    # 762. A blank (all-zero) block is all "ocean", so land is required too.
    ocean = sum(1 for v in t if v in (0, 601))
    return max(t) < 762 and ocean > 800 and ocean < len(t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", default="18,32,33,54,179")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--no-checkpoint", action="store_true")
    args = ap.parse_args()
    targets = {int(x) for x in args.targets.split(",")}
    os.makedirs(os.path.dirname(LOG), exist_ok=True)

    # `logged`: written to the log. `captured`: its checkpoint succeeded (or none was
    # wanted), so a failed checkpoint is retried on a later poll without
    # logging the map twice.
    last, stable, logged, captured = None, 0, set(), set()
    print(f"watching for tiles {sorted(targets)}; Ctrl-C to stop", flush=True)
    while True:
        try:
            t, raw = read_terrain()
        except Exception as e:  # DOSBox closed or API not up yet
            print("API not reachable:", e, flush=True)
            time.sleep(5)
            continue
        digest = hashlib.sha256(raw).hexdigest()[:12]
        stable = stable + 1 if digest == last else 0
        last = digest
        if stable >= 1 and digest not in captured and looks_like_a_map(t):
            found = {}
            for plane in (0, 1):
                c = collections.Counter(t[plane * 2400:(plane + 1) * 2400])
                for tile in targets:
                    if c[tile]:
                        found.setdefault(tile, [0, 0])[plane] = c[tile]
            if digest not in logged:
                logged.add(digest)
                row = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "map": digest, "found": found}
                with open(LOG, "a") as f:
                    f.write(json.dumps(row) + "\n")
                print(("FOUND " if found else "new map ") + json.dumps(row), flush=True)
            if found and not args.no_checkpoint:
                name = f"rare tiles {sorted(found)} map {digest}"
                done = subprocess.run(["bash", os.path.join(HERE, "live_session.sh"), "cp", name,
                                       f"terrain_watch: tile(s) {found}"], check=False)
                if done.returncode == 0:
                    captured.add(digest)
                else:
                    print(f"checkpoint failed for map {digest}; will retry", flush=True)
            else:
                captured.add(digest)
        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
