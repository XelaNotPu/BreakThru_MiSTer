#!/usr/bin/env python3
"""Generate MRA files for all Break Thru romsets (parent + clones).

All sets share the brkthru hardware/memory-map, so the RTL core (rbf 'breakthru')
runs them all; only ROM data differs.  Each MRA reuses the parent's pause-screen
asset block (embedded in the 16 KB main-ROM gap) verbatim, then loads that set's
game ROMs in the identical region layout.

ROM-name rule (matches MAME split-set behaviour): if a clone ROM's CRC equals the
parent's ROM in the same role, it is inherited from the parent zip (use the PARENT
filename); otherwise it is unique to the clone (use the clone filename).  Each MRA
lists zip="<clone>.zip|brkthru.zip" so both are searched.

Note: brkthrut's R/G PROM is a differently-wired 82S147 whose reconstructed table
is identical to the parent 13.bin, so we reuse the parent PROMs (same palette) and
avoid the overlapping ROM_CONTINUE scatter that a linear MRA cannot express.
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # sim/tools/x.py -> root
PAUSE_BIN = os.path.join(ROOT, "pause_src", "pause_assets.bin")   # packed by pack_pause.py
GAP = 0x4000

# DIP-switch footer (identical for all sets; matches the core's dsw1/dsw2 decode)
FOOTER = """\t<!-- DIP switches (brkthru): delivered to status[16+] and read by the core
\t     (BreakThru.sv dsw1_bus/dsw2_bus). base 16: DSW1=bits0-7, DSW2=bits8-12.
\t     default 7f,1f = Coin 1C/1C, slow, 1-player upright, 3 lives, 20k/30k. -->
\t<switches default="7f,1f" base="16">
\t\t<dip name="Coin A"   bits="0,1" ids="2C/1C,1C/3C,1C/2C,1C/1C"/>
\t\t<dip name="Coin B"   bits="2,3" ids="2C/1C,1C/3C,1C/2C,1C/1C"/>
\t\t<dip name="Enemy Vehicles" bits="4" ids="Fast,Slow"/>
\t\t<dip name="Enemy Bullets"  bits="5" ids="Fast,Slow"/>
\t\t<dip name="Control Panel"  bits="6" ids="2 Players,1 Player"/>
\t\t<dip name="Cabinet"        bits="7" ids="Upright,Cocktail"/>
\t\t<dip name="Lives"      bits="8,9"   ids="99 (Cheat),5,2,3"/>
\t\t<dip name="Bonus Life" bits="10,11" ids="20k Only,10k/20k,20k/40k,20k/30k"/>
\t\t<dip name="Service Mode" bits="12" ids="Off,On"/>
\t</switches>
</misterromdescription>"""

def gap_block():
    # Build the 16 KB lead-gap pause-asset <part> block from pause_assets.bin.
    blob = open(PAUSE_BIN, "rb").read()
    used = len(blob)
    lines = [" ".join("%02X" % b for b in blob[i:i+32]) for i in range(0, used, 32)]
    pad = GAP - used
    return ('\t\t<!-- 16K lead gap: PAUSE-SCREEN ASSETS (logo@0x0000, font@0x2000, text@0x2400);\n'
            '\t\t     packed by sim/tools/pack_pause.py; game ROMs still start at 0x4000 -->\n'
            '\t\t<part>\n\t\t' + '\n\t\t'.join(lines) + '\n\t\t</part>\n'
            '\t\t<part repeat="0x%X"> 00 </part>   <!-- pad assets (0x%X) up to 0x4000 -->' % (pad, used))

# parent role -> (name, crc)  (used to detect inherited ROMs by CRC)
PARENT = {
    "prog1": ("1.f9", "0f21b4c5"), "prog2": ("2.f11", "51c7c378"),
    "prog4": ("4.f14", "209484c2"), "prog3": ("3.f12", "2f2c40c2"),
    "chars": ("12.bin", "58c0b29b"),
    "tmain": ("7.b6", "920cc56a"), "tb4": ("6.b4", "fd3cee40"), "tb7": ("8.b7", "f67ee64e"),
    "spr0": ("9.bin", "f54e50a7"), "spr1": ("10.bin", "fd156945"), "spr2": ("11.bin", "c152a99b"),
    "prg": ("13.bin", "aae44269"), "prb": ("14.bin", "f2d4822a"),
    "audio": ("5.d6", "c309435f"),
}

# clone role -> (clone_name, clone_crc) exactly as in MAME ROM_START
SETS = {
    "brkthru": {"title": "Break Thru (World)", "file": "Break Thru (World).mra", "zip": "brkthru.zip", "roms": PARENT},
    "brkthruu": {"title": "Break Thru (US)", "file": "Break Thru (US).mra",
                 "zip": "brkthruu.zip|brkthru.zip", "roms": {
        "prog1": ("brkthru.1", "cfb4265f"), "prog2": ("brkthru.2", "fa8246d9"),
        "prog4": ("brkthru.4", "8cabf252"), "prog3": ("brkthru.3", "2f2c40c2"),
        "chars": ("brkthru.12", "58c0b29b"),
        "tmain": ("brkthru.7", "920cc56a"), "tb4": ("brkthru.6", "fd3cee40"), "tb7": ("brkthru.8", "f67ee64e"),
        "spr0": ("brkthru.9", "f54e50a7"), "spr1": ("brkthru.10", "fd156945"), "spr2": ("brkthru.11", "c152a99b"),
        "prg": ("brkthru.13", "aae44269"), "prb": ("brkthru.14", "f2d4822a"), "audio": ("brkthru.5", "c309435f")}},
    "brkthruj": {"title": "Kyoukou Toppa (Japan)", "file": "Break Thru (Japan).mra",
                 "zip": "brkthruj.zip|brkthru.zip", "roms": {
        "prog1": ("1", "09bd60ee"), "prog2": ("2", "f2b2cd1c"),
        "prog4": ("4", "b42b3359"), "prog3": ("brkthru.3", "2f2c40c2"),
        "chars": ("12", "3d9a7003"),
        "tmain": ("brkthru.7", "920cc56a"), "tb4": ("6", "cb47b395"), "tb7": ("8", "5e5a2cd7"),
        "spr0": ("brkthru.9", "f54e50a7"), "spr1": ("brkthru.10", "fd156945"), "spr2": ("brkthru.11", "c152a99b"),
        "prg": ("brkthru.13", "aae44269"), "prb": ("brkthru.14", "f2d4822a"), "audio": ("brkthru.5", "c309435f")}},
    "brkthrut": {"title": "Break Thru (Tecfri)", "file": "Break Thru (Tecfri).mra",
                 "zip": "brkthrut.zip|brkthru.zip", "roms": {
        "prog1": ("5_de-0230-2_27128.f9", "158e660a"), "prog2": ("6_de-0230-2_27256.f11", "62dbe49e"),
        "prog4": ("8_de-0230-2_27256.f13", "8cabf252"), "prog3": ("7_de-0230-2_27256.f12", "2f2c40c2"),
        "chars": ("9_de-0231-2_2764.c8", "58c0b29b"),
        "tmain": ("2_de-0230-2_27256.a6", "920cc56a"), "tb4": ("1_de-0230-2_27256.a5", "fd3cee40"),
        "tb7": ("3_de-0230-2_27256.a8", "f67ee64e"),
        "spr0": ("10_de-0231-2_27156.h2", "f54e50a7"), "spr1": ("11_de-0231-2_27156.h4", "fd156945"),
        "spr2": ("12_de-0231-2_27156.h5", "c152a99b"),
        # R/G reconstructed == parent 13.bin; reuse parent PROMs (same palette)
        "prg": ("13.bin", "aae44269"), "prb": ("14.bin", "f2d4822a"),
        "audio": ("4_de-0230-2_27256.d6", "c309435f")}},
    "forcebrk": {"title": "Force Break (bootleg)", "file": "Force Break.mra",
                 "zip": "forcebrk.zip|brkthru.zip", "roms": {
        "prog1": ("1", "09bd60ee"), "prog2": ("2", "f2b2cd1c"),
        "prog4": ("forcebrk4", "b4838c19"), "prog3": ("brkthru.3", "2f2c40c2"),
        "chars": ("12", "3d9a7003"),
        "tmain": ("brkthru.7", "920cc56a"), "tb4": ("forcebrk6", "08bca16a"), "tb7": ("forcebrk8", "a3a1131e"),
        "spr0": ("brkthru.9", "f54e50a7"), "spr1": ("brkthru.10", "fd156945"), "spr2": ("brkthru.11", "c152a99b"),
        "prg": ("brkthru.13", "aae44269"), "prb": ("brkthru.14", "f2d4822a"), "audio": ("brkthru.5", "c309435f")}},
}

def resolve(role, clone_name, clone_crc):
    """Inherited ROM (same CRC as parent) -> parent filename; else clone name."""
    pname, pcrc = PARENT[role]
    if clone_crc.lower() == pcrc.lower():
        return pname, pcrc
    return clone_name, clone_crc

def tiles_block(tmain, tb4, tb7):
    m, mc = tmain; b4, b4c = tb4; b7, b7c = tb7
    L = []
    L.append('\t\t<part name="%s" crc="%s" offset="0x0000" length="0x4000"/>  <!-- 0x00000 -->' % (m, mc))
    L.append('\t\t<part name="%s" crc="%s" offset="0x0000" length="0x1000"/>  <!-- 0x04000 -->' % (b7, b7c))
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x1000" length="0x1000"/>  <!-- 0x06000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x4000" length="0x4000"/>  <!-- 0x08000 -->' % m)
    L.append('\t\t<part name="%s" offset="0x2000" length="0x1000"/>  <!-- 0x0C000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x3000" length="0x1000"/>  <!-- 0x0E000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" crc="%s" offset="0x0000" length="0x4000"/>  <!-- 0x10000 -->' % (b4, b4c))
    L.append('\t\t<part name="%s" offset="0x4000" length="0x1000"/>  <!-- 0x14000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x5000" length="0x1000"/>  <!-- 0x16000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x4000" length="0x4000"/>  <!-- 0x18000 -->' % b4)
    L.append('\t\t<part name="%s" offset="0x6000" length="0x1000"/>  <!-- 0x1C000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    L.append('\t\t<part name="%s" offset="0x7000" length="0x1000"/>  <!-- 0x1E000 -->' % b7)
    L.append('\t\t<part repeat="0x1000"> 00 </part>')
    return "\n".join(L)

def main():
    gap = gap_block()
    footer = FOOTER

    for setname, s in SETS.items():
        r = {role: resolve(role, *s["roms"][role]) for role in PARENT}
        def p(role, comment=""):
            n, c = r[role]
            return '\t\t<part name="%s" crc="%s"/>%s' % (n, c, ("   <!-- %s -->" % comment) if comment else "")
        body = []
        body.append('<misterromdescription>')
        body.append('\t<name>%s</name>' % s["title"])
        body.append('\t<setname>%s</setname>' % setname)
        body.append('\t<rbf>xnbrkthru</rbf>')   # matches _Arcade/cores/xnbrkthru_YYYYMMDD.rbf
        body.append('\t<mameversion>0262</mameversion>')
        body.append('\t<year>1986</year>')
        body.append('\t<manufacturer>Data East</manufacturer>')
        body.append('\t<players>2</players>')
        body.append('\t<buttons names="Fire/Button1,Accelerate/Button2,-,-,-,-,Coin,Start,Pause" default="A,B,R,Start,Select" count="2"/>')
        body.append('')
        body.append('\t<rom index="0" zip="%s" md5="none">' % s["zip"])
        body.append('\t\t<!-- maincpu region 0x20000: 16K lead gap (pause assets), then program ROMs -->')
        body.append(gap)
        body.append(p("prog1", "0x04000"))
        body.append(p("prog2", "0x08000"))
        body.append(p("prog4", "0x10000"))
        body.append(p("prog3", "0x18000"))
        body.append('')
        body.append('\t\t<!-- chars region 0x2000 -->')
        body.append(p("chars"))
        body.append('')
        body.append('\t\t<!-- tiles region 0x20000 : MAME scatter -->')
        body.append(tiles_block(r["tmain"], r["tb4"], r["tb7"]))
        body.append('')
        body.append('\t\t<!-- sprites region 0x18000 -->')
        body.append(p("spr0", "plane 0")); body.append(p("spr1", "plane 1")); body.append(p("spr2", "plane 2"))
        body.append('')
        body.append('\t\t<!-- proms region 0x200 -->')
        body.append(p("prg", "R/G")); body.append(p("prb", "B"))
        body.append('')
        body.append('\t\t<!-- audiocpu region : sound program 8000-FFFF (32K) -->')
        body.append(p("audio"))
        body.append('\t</rom>')
        body.append('')
        body.append(footer.rstrip("\n"))
        out = "\n".join(body) + "\n"
        with open(os.path.join(ROOT, "releases", s["file"]), "w") as f:
            f.write(out)
        uniq = sum(1 for role in PARENT if r[role][1].lower() != PARENT[role][1].lower())
        print("wrote %-28s setname=%-9s zip=%-24s unique-ROMs=%d" % (s["file"], setname, s["zip"], uniq))

if __name__ == "__main__":
    main()
