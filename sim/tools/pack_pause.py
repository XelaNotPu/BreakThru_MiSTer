#!/usr/bin/env python3
"""Pack the pause-screen assets (XN logo + 5x8 font + centered NFO) into the
16 KB lead gap of the main-CPU ROM and embed them into the MRA.

Gap layout (main-ROM dpram 0x0000-0x3FFF, never addressed by the game):
  0x0000  LOGO : 128x128, 4bpp, 2px/byte (hi nibble = even x), row-major
  0x2000  FONT : 128 chars x 8 rows, low 5 bits = 5 px (bit4 = leftmost)
  0x2400  TEXT : STRIDE(64) cols x ROWS rows of ASCII; NCOLS(51) rendered, centered

Font dims (FW=5, FH=8, NCOLS=51, STRIDE=64, ROWS=72) are baked into
rtl/brkthru_pause.sv - keep them in sync.  The NFO *content* (pause_src/pause.txt)
is runtime-loaded via the MRA, so editing it only needs a re-pack + MRA reload,
NOT a Quartus recompile (as long as it stays <= NCOLS wide and <= ROWS lines).

Usage: pack_pause.py <logo_128.rgb> [mra_path]
  <logo_128.rgb> = 128x128 RGB24 raw (ffmpeg -vf scale=128:128 -pix_fmt rgb24)
"""
import sys, os, json, re

FW, FH, NCOLS, STRIDE, ROWS = 5, 8, 51, 64, 72
LOGO_OFF, FONT_OFF, TEXT_OFF = 0x0000, 0x2000, 0x2400
GAP = 0x4000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))   # sim/tools -> project root
FONT_JSON = os.path.join(ROOT, "pause_src", "font_5x8.json")
# Editable NFO content (in-repo, self-contained). Each line is auto-centered
# within NCOLS(51); keep lines <= ~48 chars and <= ROWS(72) lines. Printable
# ASCII only. Editing this file then re-running the packer + reloading the MRA
# updates the pause text with NO Quartus recompile (only the 5x8 font geometry
# is baked into the RTL).
NFO = os.path.join(ROOT, "pause_src", "pause.txt")
# Downscaled logo raw (128x128 RGB24). Regenerate from the in-repo source PNG:
#   ffmpeg -y -i pause_src/XN-Circle-Smaller-8bit.png -vf scale=128:128:flags=lanczos \
#          -pix_fmt rgb24 -f rawvideo pause_src/xn_128.rgb
DEFAULT_RGB = os.path.join(ROOT, "pause_src", "xn_128.rgb")

def medcut(cols, n):
    boxes = [list(cols)]
    while len(boxes) < n:
        best, bi = -1, 0
        for i, b in enumerate(boxes):
            if len(b) < 2: continue
            rng = max(max(c[k] for c in b)-min(c[k] for c in b) for k in range(3))*len(b)
            if rng > best: best, bi = rng, i
        b = boxes.pop(bi)
        ch = max(range(3), key=lambda k: max(c[k] for c in b)-min(c[k] for c in b))
        b.sort(key=lambda c: c[ch]); m = len(b)//2
        boxes.append(b[:m]); boxes.append(b[m:])
    return [tuple(sum(c[k] for c in b)//(len(b) or 1) for k in range(3)) for b in boxes]

def main():
    rgb = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_RGB
    mra = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "releases", "Break Thru (World).mra")
    font = {int(k): v for k, v in json.load(open(FONT_JSON)).items()}

    raw = open(NFO).read().split("\n")
    def norm(l):
        l = l.replace("\t", "    ").rstrip()[:NCOLS]
        return (" " * ((NCOLS - len(l)) // 2)) + l
    lines = [norm(l) for l in raw]
    while lines and lines[-1].strip() == "":
        lines.pop()
    if len(lines) > ROWS:
        raise SystemExit("pause.txt has %d lines > ROWS=%d" % (len(lines), ROWS))
    lines += [""] * (ROWS - len(lines))
    maxw = max(len(l) for l in lines)

    blob = bytearray(GAP)
    lr = open(rgb, "rb").read(); LW = LH = 128
    px = [(lr[i*3], lr[i*3+1], lr[i*3+2]) for i in range(LW*LH)]
    pal = medcut(px, 16)
    idx = [min(range(16), key=lambda i: sum((c[k]-pal[i][k])**2 for k in range(3))) for c in px]
    for y in range(LH):
        for x in range(0, LW, 2):
            blob[LOGO_OFF + y*64 + x//2] = ((idx[y*LW+x] & 0xF) << 4) | (idx[y*LW+x+1] & 0xF)
    for c in range(128):
        g = font.get(c)
        for r in range(8):
            byte = 0
            if g and r < FH:
                for fx in range(FW):
                    if g[r][fx]: byte |= (1 << (FW-1-fx))
            blob[FONT_OFF + c*8 + r] = byte
    for r in range(ROWS):
        for c in range(NCOLS):
            ch = ord(lines[r][c]) if c < len(lines[r]) and 32 <= ord(lines[r][c]) < 127 else 32
            blob[TEXT_OFF + r*STRIDE + c] = ch

    used = TEXT_OFF + ROWS*STRIDE
    open(os.path.join(ROOT, "pause_src", "pause_assets.bin"), "wb").write(blob[:used])
    with open(os.path.join(ROOT, "sim", "pause_gap.hex"), "w") as f:
        f.write("\n".join("%02x" % b for b in blob) + "\n")

    hexbytes = [b for b in blob[:used]]
    hexlines = [" ".join("%02X" % b for b in hexbytes[i:i+32]) for i in range(0, len(hexbytes), 32)]
    pad = GAP - used
    block = ('\t\t<!-- 16K lead gap: PAUSE-SCREEN ASSETS (logo@0x0000, font@0x2000, text@0x2400);\n'
             '\t\t     packed by sim/tools/pack_pause.py; game ROMs still start at 0x4000 -->\n'
             '\t\t<part>\n\t\t' + '\n\t\t'.join(hexlines) + '\n\t\t</part>\n'
             '\t\t<part repeat="0x%X"> 00 </part>   <!-- pad assets (0x%X) up to 0x4000 -->' % (pad, used))
    s = open(mra).read()
    pat = re.compile(r'\t\t<!-- 16K lead gap: PAUSE-SCREEN ASSETS.*?<part repeat="0x[0-9A-Fa-f]+"> 00 </part>   <!-- pad assets.*?-->', re.S)
    if pat.search(s):
        s = pat.sub(block, s)
    else:
        s = s.replace('\t\t<part repeat="0x4000"> 00 </part>', block)
    open(mra, "w").write(s)

    json.dump(pal, open(os.path.join(ROOT, "pause_src", "logo_pal.json"), "w"))
    print("packed: ROWS=%d maxw=%d NCOLS=%d used=0x%X pad=0x%X" % (ROWS, maxw, NCOLS, used, pad))
    print("PALETTE (rtl/brkthru_pause.sv localparams):")
    for i, (r, g, b) in enumerate(pal):
        print("  %2d: 24'h%02X%02X%02X" % (i, r, g, b))

if __name__ == "__main__":
    main()
