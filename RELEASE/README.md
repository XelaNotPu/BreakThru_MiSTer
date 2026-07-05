# Break Thru — MiSTer FPGA Arcade Core

An FPGA implementation of Data East's 1986 arcade game **Break Thru**
(Japanese title *Kyohkoh-Toppa*, MAME set `brkthru`) for the
[MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

> ⚖️ *"Break Thru", Data East, and all related names and assets are the property
> of their respective owners. This is an independent, non-commercial preservation
> project and ships **no** game ROMs or assets. See the
> [Trademarks & Copyright Disclaimer](#trademarks--copyright-disclaimer) below
> (also [`DISCLAIMER.md`](./DISCLAIMER.md)).*

---

## What this is

Break Thru is a horizontally-scrolling driving/shooting game where you pilot the
experimental "Break Thru" vehicle across enemy territory to recover a stolen
fighter jet. This core is a from-scratch hardware re-creation of the original
Data East arcade PCB, cycle-driven from the same 12 MHz master clock and running
the game's original program ROMs.

The core reproduces the PCB at the hardware level:

- **Main CPU:** Motorola MC6809 (HD6809EP)
- **Sound CPU:** Motorola MC6809E (HD68A09P) driven by a sound latch (NMI/poll)
- **Sound chips:** YM2203 (OPN) + YM3526 (OPL), mixed to mono
- **Video:** 256×240 visible, ~57.44 Hz, 15 kHz horizontal
  - Foreground/text tilemap (8×8, 3 bpp, 32×32)
  - Background tilemap (16×16 tiles, banked, horizontal scroll)
  - Sprites (16×16 with a 16×32 double-height mode)
  - Two palette PROMs (256×8 R/G + 256×4 B) decoded to 24-bit RGB

No ROM images are included or distributed with this core. You must supply your
own `brkthru.zip` (see **Installation**).

---

## Why?

I wanted to play Break Thru on my MiSTer...

---
## Implemented features & current status

Hardware-verified on a real MiSTer (DE10-Nano) on 2026-07-04: the attract screen
and gameplay render correctly — background scenery, foreground HUD, player sprite,
and palette all compose correctly on real silicon.

| Subsystem | Status |
|---|---|
| Clocks & video timing (6 MHz pixel, `set_raw` H/V counters) | Implemented, verified |
| Main CPU MC6809 + full memory map + ioctl ROM load + IRQ/NMI | Implemented, sim-verified, on hardware |
| Foreground text tilemap | Implemented, verified (HUD renders) |
| Background tilemap (banked 16×16 tiles + scroll) | Implemented, verified |
| Sprites (line-buffer, double-height, priority mix) | Implemented, verified on hardware |
| Palette (dual-PROM decode → RGB888) | Implemented, verified |
| Inputs (joystick, buttons, coin-edge → IRQ) | Implemented, on hardware |
| DIP switches (via MRA `<switches>` / OSD DIP page) | Implemented, on hardware |
| Sound (2nd MC6809, latch/NMI, YM2203 + YM3526, mono mix) | Implemented; music verified on hardware, SFX balance being finalized |

**Known limitations / not yet done:**

- **Flip-screen / cocktail mode** is not implemented (upright only).
- **Sound SFX mix balance** is still being finalized on hardware; music plays
  correctly. See the project's `docs/status.md` for the running investigation log.
- **Service DIP** is currently forced off in RTL as an interim fix so the game
  boots to attract/gameplay reliably.
- The design fills BRAM at ~100% (553/553 M10K blocks) with thin timing slack —
  a design change may require a re-seed or BRAM compaction.
---

## Installation

This core does **not** include any ROM data. You provide your own dump.

1. Copy the compiled bitstream to your MiSTer SD card under `_Arcade/cores/`
   as `xnbrkthru_YYYYMMDD.rbf` (e.g. `xnbrkthru_20260705.rbf`).
2. Copy **`Break Thru (World).mra`** into your `_Arcade/` folder, and the regional
   variants (US / Japan / Tecfri / Force Break) into
   `_Arcade/_alternatives/_Breakthru/`.
3. Place your own **`brkthru.zip`** (the MAME `brkthru` parent set) into
   `games/mame/` (or `_Arcade/mame/`) on the SD card — plus each clone's zip
   (`brkthruu.zip`, `brkthruj.zip`, `brkthrut.zip`, `forcebrk.zip`) if you want the
   variants. The MRA references the ROMs by name and CRC and assembles them at load
   time — no ROMs are shipped here.
4. Launch the **Break Thru** entry from the MiSTer arcade menu.

The `.mra` files set `<rbf>xnbrkthru</rbf>` (matching the dated `xnbrkthru_YYYYMMDD.rbf`
core) and the appropriate `<setname>` per set.

---

## Controls

Default MiSTer button mapping (from the MRA `<buttons>` list and core `CONF_STR`):

| Function | Control |
|---|---|
| Move | 8-way joystick / D-pad |
| Fire (Button 1) | mapped joystick button |
| Accelerate (Button 2) | mapped joystick button |
| Insert Coin | Coin (framework joy bit 10) |
| Start | Start (framework joy bit 11) |
| Pause | Pause (framework joy bit 12) |

Two players are supported (alternating play). Player-2 inputs share the same
mapping on the second controller.

---

## DIP switches

Delivered through the MRA `<switches base="16">` block and adjustable from the
MiSTer OSD **DIP** page. Defaults (`7f,1f`) match the MAME `brkthru` defaults.

| Switch | Options |
|---|---|
| Coin A | 2C/1C, 1C/3C, 1C/2C, 1C/1C |
| Coin B | 2C/1C, 1C/3C, 1C/2C, 1C/1C |
| Enemy Vehicles | Fast / Slow |
| Enemy Bullets | Fast / Slow |
| Control Panel | 2 Players / 1 Player |
| Cabinet | Upright / Cocktail |
| Lives | 99 (Cheat), 5, 2, 3 |
| Bonus Life | 20k only, 10k/20k, 20k/40k, 20k/30k |
| Service Mode | Off / On |

---

## Source layout

- `rtl/` — game RTL (`brkthru_*.sv`, clocks, video timing, palette, inputs)
- `rtl/cpu/` — MC6809 core
- `rtl/sound/` — YM2203 / SSG / YM3526 cores
- `rtl/mem/`, `rtl/pll/` — dual-port RAM inference and PLL
- `sys/` — MiSTer framework (do not modify)
- `releases/` — the MRA
- `docs/` — hardware notes, ROM map, decode notes, build status

---

## Credits

- **Break Thru core** — XelaNotPu (game RTL, memory map, video/sound
  integration, MRA).
- **MC6809 CPU core (`mc6809i`)** — Greg Miller, "Cycle-Accurate 6809 Core".
- **JT sound cores (`jt12`/`jt03`, `jt49`, `jtopl`)** — Jose Tejada (jotego,
  Twitter [@topapate](https://twitter.com/topapate)).
- **MiSTer framework (`sys/`)** — the MiSTer-devel project; Till Harbaum
  (original `hps_io`) and Alexey Melnikov ("Sorgelig") et al.
- **Hardware reference** — the MAME `brkthru` driver
  (`src/mame/dataeast/brkthru.cpp`) is the authoritative source of behavior.

Break Thru / *Kyohkoh-Toppa* and all game assets are © 1986 Data East. This core
contains **no** game ROM data and is not affiliated with or endorsed by Data East
or its successors.

---

## License & Attribution

This core is a combined/derivative work that includes third-party RTL licensed
under the **GNU General Public License, version 3**. The vendored Jotego JT sound
cores are GPLv3-or-later, and the MiSTer framework files under `sys/` are also
GPLv3-or-later. Because GPLv3 code is compiled into the core, **the core as a
whole — including the synthesized bitstream (`.rbf`) — is distributed under the
GNU General Public License, version 3.** See [`LICENSE`](./LICENSE) for the full
text and [`THIRD-PARTY-NOTICES.md`](./THIRD-PARTY-NOTICES.md) for per-component
copyright notices.

### Component licenses

| Component | Path | Author(s) | License | Upstream |
|---|---|---|---|---|
| MC6809 CPU core (`mc6809i.v`) | `rtl/cpu/` | Greg Miller (© 2016) | BSD-3-Clause ("Standard BSD", elected — GPL-compatible; see note below) | https://github.com/cavnex/mc6809 |
| JT12 / JT03 (YM2203) | `rtl/sound/jt12/` | Jose Tejada (jotego) | GPL-3.0-or-later | https://github.com/jotego/jt12 |
| JT49 (SSG / AY) | `rtl/sound/jt49/` | Jose Tejada (jotego) | GPL-3.0-or-later | https://github.com/jotego/jt49 |
| JTOPL (YM3526) | `rtl/sound/jtopl/` | Jose Tejada (jotego) | GPL-3.0-or-later | https://github.com/jotego/jtopl |
| MiSTer framework | `sys/` | Till Harbaum, Alexey Melnikov (Sorgelig) et al. | GPL-3.0-or-later (per-file headers) | https://github.com/MiSTer-devel/Template_MiSTer |
| Break Thru game RTL | `rtl/brkthru_*.sv`, clocks, video timing, palette, inputs, `rtl/mem`, `rtl/pll` | This project | GPL-3.0 (as part of the combined work) | — |

> **Note on `mc6809i.v`:** the vendored file carries only `Copyright (c) 2016,
> Greg Miller` in its header, but the upstream project
> ([github.com/cavnex/mc6809](https://github.com/cavnex/mc6809),
> `documentation/LICENSE.md`) offers a choice of two licenses ("You must select
> one"): a **Standard BSD** (BSD-3-Clause) license permitting source + binary
> redistribution, and a **Modified BSD** license that is binary-only. **This
> project elects the Standard BSD (BSD-3-Clause) license**, which is
> GPL-compatible and permits source redistribution, so `mc6809i.v` may be combined
> into this GPL-3.0 work. Its required copyright notice, conditions, and disclaimer
> are reproduced in full in `rtl/cpu/NOTICE.md` and `THIRD-PARTY-NOTICES.md`.

### Your obligations under GPLv3

When you redistribute this core (source or bitstream), you must:

1. **Provide the complete corresponding source** for the version you distribute
   (this repository).
2. **Preserve all copyright and permission notices** in the source, including the
   Jotego JT headers, the MiSTer/`sys` headers, and Greg Miller's copyright.
3. **Disclose modifications** made to GPL components (see below), carrying
   prominent notices that you changed the files and when.
4. **Keep the same license** (GPLv3) on the whole combined work.

### Disclosure of modifications

Per GPLv3 §5 (stated changes), the following modification was made to a vendored
GPL file:

- **`rtl/sound/jt12/jt12_top.v`** — one minimal bug fix: the unconditional
  `assign fm_snd_left/right = accum_l/r[...]` (the YM2612 accumulator sum) was
  moved inside a `generate if (use_pcm==1)` block. In this older jt12 copy it
  collided with the YM2203 branch (`gen_2203_acc`, which drives
  `fm_snd_* = mono_snd`), producing a Quartus multiple-constant-drivers error for
  the `jt03` (`use_pcm==0`) configuration. The change is marked in-file with a
  `BreakThru_MiSTer fix:` comment. YM2612 behavior is unchanged. See
  `rtl/sound/NOTICE.md`.

All other vendored files are used verbatim; `mc6809i.v` is copied unmodified.

---

## Trademarks & Copyright Disclaimer

**"Break Thru"** (Japanese title **"Kyohkoh-Toppa" / 強行突破**), together with the
game itself and all of its associated titles, names, logos, characters, artwork,
graphics, music, sound, and other audiovisual assets and content, are trademarks
and/or copyrighted works of **Data East Corporation** and/or its respective
owners, successors, assignees, licensees, and rights holders. All such rights are
and remain the **sole and exclusive property of their respective owners.**

This project (the "Core") is an **independent, non-commercial, hobbyist
hardware-description (FPGA) reimplementation** of the original arcade hardware,
created solely for the purposes of **education, research, interoperability,
technical study, and the preservation of arcade game history.** It is a clean
reimplementation of digital logic behavior; it contains **no** copyrighted ROM
images, game code, graphics, audio, or other game assets belonging to any rights
holder.

- This project is **not affiliated with, authorized by, endorsed by, sponsored
  by, or associated with** Data East Corporation or any other rights holder, and
  no such affiliation or endorsement is claimed or implied.
- Any and all trademarks and copyrighted names appearing in this repository,
  documentation, or user interface are used **for identification and descriptive
  purposes only** (nominative fair use) to indicate the hardware this Core is
  compatible with. Such use does **not** constitute or imply any claim of
  ownership, sponsorship, or endorsement.
- **No game ROMs or copyrighted game assets are distributed** with this project.
  To run the Core you must supply your own game data, which you must legally own
  or otherwise be lawfully entitled to use. You are solely responsible for
  ensuring that your use of any game data complies with all applicable laws in
  your jurisdiction.
- This project is a **derivative implementation of hardware behavior** and does
  not reproduce or distribute the original manufacturer's copyrighted program or
  data. It is offered under the GNU General Public License v3 (see above) with
  respect to the **project's own and its vendored open-source source code only**,
  and confers **no rights whatsoever** in any third-party game intellectual
  property.

No copyright or trademark infringement is intended. If you are a rights holder
and believe any content in this repository infringes your rights, please contact
the maintainer and any such content will be promptly reviewed and, where
appropriate, removed.

THE CORE AND ALL ASSOCIATED FILES ARE PROVIDED **"AS IS", WITHOUT WARRANTY OF ANY
KIND**, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO
EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR
OTHER LIABILITY ARISING FROM, OUT OF, OR IN CONNECTION WITH THE CORE OR ITS USE.
