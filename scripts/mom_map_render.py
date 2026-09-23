#!/usr/bin/env python3
"""Render a Master of Magic save's overland map straight from the game's own LBX art.

No smoothing, no classification: each u16 terrain value in the save is a tile
number, and TERRAIN.LBX already holds the fully-resolved tile for it.

Reference implementation for docs/reference/classic-terrain-format.md.

Usage:
  python3 mom_map_render.py SAVE1.GAM --lbx /path/to/MoM [--scale 2] [--frame 0] [--out out_dir]
                            [--minimap] [--sheet]
"""
import argparse, os, struct, sys
from PIL import Image

W, H = 60, 40                 # map size in tiles
TW, TH = 20, 18               # tile size in pixels
TILES_PER_PLANE = 762         # 0x2FA
TERRAIN_OFFSET = 0x2698       # u16 x 2400 per plane, Arcanus then Myrror
REC = 384                     # bytes per tile record in TERRAIN.LBX (16 hdr + 360 px + 8 pad)


def lbx_entries(data):
    n = struct.unpack_from('<H', data, 0)[0]
    offs = struct.unpack_from('<%dI' % (n + 1), data, 8)
    return [data[offs[i]:offs[i + 1]] for i in range(n)], offs


def find(dirpath, name):
    for f in os.listdir(dirpath):
        if f.upper() == name:
            return os.path.join(dirpath, f)
    sys.exit(f'{name} not found in {dirpath}')


def load_palette(lbx_dir):
    fonts = open(find(lbx_dir, 'FONTS.LBX'), 'rb').read()
    entries, _ = lbx_entries(fonts)
    raw = entries[2][:768]    # 6-bit VGA RGB triplets, scaled like Mirror.LBX.Palette
    return [tuple(min(255, round(c * 255 / 63)) for c in raw[i * 3:i * 3 + 3]) for i in range(256)]


class Terrain:
    def __init__(self, lbx_dir, palette):
        self.data = open(find(lbx_dir, 'TERRAIN.LBX'), 'rb').read()
        entries, _ = lbx_entries(self.data)
        self.ptr = struct.unpack_from('<%dH' % (2 * TILES_PER_PLANE), entries[1])
        self.minimap = entries[2]
        self.pal = palette
        self.cache = {}

    def record(self, value, plane):
        """(record index, animated?) for a terrain value. EMS-style pointer:
        low 7 bits / 3 = 48KB bank (128 records), high byte = record in bank."""
        w = self.ptr[plane * TILES_PER_PLANE + value]
        return ((w & 0x7F) // 3) * 128 + (w >> 8), bool(w & 0x80)

    def tile(self, value, plane, frame=0):
        key = (value, plane, frame)
        if key not in self.cache:
            k, animated = self.record(value, plane)
            if animated:
                k += frame % 4
            base = k * REC + 16
            px = self.data[base:base + TW * TH]
            im = Image.new('RGB', (TW, TH))
            im.putdata([self.pal[px[x * TH + y]] for y in range(TH) for x in range(TW)])  # column-major
            self.cache[key] = im
        return self.cache[key]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('save', help='SAVEn.GAM file')
    ap.add_argument('--lbx', required=True, help='directory containing TERRAIN.LBX and FONTS.LBX')
    ap.add_argument('--out', default='.', help='output directory')
    ap.add_argument('--scale', type=int, default=1, help='integer upscale (nearest neighbour)')
    ap.add_argument('--frame', type=int, default=0, help='animation frame 0-3 for water/animated tiles')
    ap.add_argument('--gif', action='store_true', help='also write a 4-frame animated GIF per plane')
    ap.add_argument('--minimap', action='store_true', help='also write the 60x40 minimap (TERRAIN.LBX entry 2)')
    ap.add_argument('--sheet', action='store_true', help='also write a contact sheet of all 762 tiles per plane')
    a = ap.parse_args()

    pal = load_palette(a.lbx)
    terr = Terrain(a.lbx, pal)
    save = open(a.save, 'rb').read()
    os.makedirs(a.out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.save))[0]

    def up(im):
        return im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST) if a.scale > 1 else im

    for plane, name in ((0, 'arcanus'), (1, 'myrror')):
        vals = struct.unpack_from('<%dH' % (W * H), save, TERRAIN_OFFSET + plane * W * H * 2)

        def render(frame):
            out = Image.new('RGB', (W * TW, H * TH))
            for i, v in enumerate(vals):
                out.paste(terr.tile(v, plane, frame), ((i % W) * TW, (i // W) * TH))
            return up(out)

        path = os.path.join(a.out, f'{stem}_{name}.png')
        render(a.frame).save(path); print(path)

        if a.gif:
            frames = [render(f) for f in range(4)]
            path = os.path.join(a.out, f'{stem}_{name}.gif')
            frames[0].save(path, save_all=True, append_images=frames[1:], duration=250, loop=0); print(path)

        if a.minimap:
            mm = Image.new('RGB', (W, H))
            mm.putdata([pal[terr.minimap[plane * TILES_PER_PLANE + v]] for v in vals])
            path = os.path.join(a.out, f'{stem}_{name}_minimap.png')
            mm.resize((W * 4 * a.scale, H * 4 * a.scale), Image.NEAREST).save(path); print(path)

        if a.sheet:
            cols = 32
            sheet = Image.new('RGB', (cols * (TW + 1), (TILES_PER_PLANE // cols + 1) * (TH + 1)), (40, 40, 40))
            for v in range(TILES_PER_PLANE):
                sheet.paste(terr.tile(v, plane), ((v % cols) * (TW + 1), (v // cols) * (TH + 1)))
            path = os.path.join(a.out, f'tiles_{name}.png')
            up(sheet).save(path); print(path)


if __name__ == '__main__':
    main()
