# Third-Party Notices

The Break Thru MiSTer core incorporates the third-party components listed below.
Each entry reproduces the copyright/attribution as found in the actual source
file headers, states its license, and points to where the full license text
lives. The core as a whole is distributed under **GPL-3.0** (see `LICENSE`);
because the Jotego JT sound cores and the MiSTer `sys/` framework files are
GPL-3.0-or-later, GPLv3 governs the combined work and its synthesized bitstream.

---

## 1. MC6809 CPU core — `mc6809i.v`

- **Location in source tree:** `rtl/cpu/mc6809i.v`
- **Attribution (verbatim from the file header):**
  - `Engineer: Greg Miller`
  - `Copyright (c) 2016, Greg Miller`
  - `Project Name:   Cycle-Accurate 6809 Core`
- **License:** **BSD 3-Clause** ("Standard BSD"). The upstream project
  (https://github.com/cavnex/mc6809, `documentation/LICENSE.md`) is offered under a
  choice of two licenses and states *"You must select one"*: a "Standard BSD"
  license (permits source **and** binary redistribution) and a "Modified BSD"
  license (binary-only, source redistribution prohibited). **This project elects
  the Standard BSD (BSD 3-Clause) license**, which permits source redistribution
  and is a GPL-compatible license (per the FSF's list of GPL-compatible licenses),
  so it may be combined into this GPL-3.0 work. The vendored file carries only the
  copyright line; the full license text below is reproduced here to satisfy the
  Standard BSD requirement to retain the copyright notice, conditions, and
  disclaimer with source and binary redistributions.
- **Full license text (Standard BSD, verbatim from upstream `LICENSE.md`):**

  ```
  Copyright (c) 2016, Greg Miller
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.
      * The name of the author may not be used to endorse or promote products
        derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL GREG MILLER BE LIABLE FOR ANY
  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  ```
- **Provenance / modifications:** Obtained from the Jotego JTFRAME tree
  (`modules/jtframe/hdl/cpu/mc6809i.v`); original upstream is
  https://github.com/cavnex/mc6809. Copied **verbatim, unmodified**; original
  header preserved. Driven directly (no JTFRAME `jtframe_sys6809` wrapper). See
  `rtl/cpu/NOTICE.md`.
- **Upstream:** https://github.com/cavnex/mc6809 (also redistributed via
  https://github.com/jotego/jtframe)

---

## 2. JT12 / JT03 — YM2203 (OPN) FM + SSG

- **Location in source tree:** `rtl/sound/jt12/`
- **Attribution (verbatim from file headers, e.g. `jt03.v`):**
  - `This file is part of JT12.`
  - `Author: Jose Tejada Gomez. Twitter: @topapate`
- **License:** **GNU General Public License, version 3 or (at your option) any
  later version** — stated in every source header:
  *"JT12 program is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation, either version 3 of the License, or (at your option) any later
  version."*
- **Full license text:** `rtl/sound/jt12/LICENSE` (full GPLv3), mirrored in this
  release as `LICENSE`.
- **Upstream:** https://github.com/jotego/jt12
- **Modifications:** **`rtl/sound/jt12/jt12_top.v` was modified** — see the
  "Stated changes" section below. All other jt12 files are used verbatim.

---

## 3. JT49 — SSG / AY-3-8910-style sound generator

- **Location in source tree:** `rtl/sound/jt49/`
- **Attribution (verbatim from file headers, e.g. `jt49.v`):**
  - `This file is part of JT49.`
  - `Author: Jose Tejada Gomez. Twitter: @topapate`
  - `Based on sqmusic, by the same author`
- **License:** **GNU General Public License, version 3 or (at your option) any
  later version** — stated in every source header.
- **Full license text:** `rtl/sound/jt49/LICENSE` (full GPLv3).
- **Upstream:** https://github.com/jotego/jt49
- **Modifications:** none — used verbatim.

---

## 4. JTOPL — YM3526 (OPL)

- **Location in source tree:** `rtl/sound/jtopl/`
- **Attribution (verbatim from file headers, e.g. `jtopl.v`):**
  - `This file is part of JTOPL.`
  - `Author: Jose Tejada Gomez. Twitter: @topapate`
- **License:** **GNU General Public License, version 3 or (at your option) any
  later version** — stated in every source header.
- **Full license text:** `rtl/sound/jtopl/LICENSE` (full GPLv3).
- **Upstream:** https://github.com/jotego/jtopl
- **Modules used:** `jtopl` (the YM3526 OPL). Not used: `jtopl2` (YM3812),
  `jt2413`, `jtopll_*` (OPLL).
- **Modifications:** none — used verbatim.

---

## 5. MiSTer framework — `sys/`

- **Location in source tree:** `sys/` (copied unmodified from the MiSTer template)
- **Attribution (verbatim from file headers, e.g. `sys/hps_io.sv`):**
  - `Copyright (c) 2014 Till Harbaum <till@harbaum.org>`
  - `Copyright (c) 2017-2026 Alexey Melnikov`
  - (plus additional MiSTer-devel contributors across other `sys/` files)
- **License:** The individual `sys/` source files carry **GPL-3.0-or-later**
  headers: *"free software: you can redistribute it and/or modify it under the
  terms of the GNU General Public License ... either version 3 of the License, or
  (at your option) any later version."* Note: the upstream template's top-level
  `LICENSE` file is GPLv2; the framework source files themselves are GPLv3+.
- **Upstream:** https://github.com/MiSTer-devel/Template_MiSTer
- **Modifications:** none — `sys/` is used as-is per MiSTer policy.

---

## 6. Break Thru game RTL (this project)

- **Location in source tree:** `rtl/brkthru_*.sv`, `rtl/breakthru_*.sv`,
  `rtl/brkthru_palette.sv`, `rtl/brkthru_inputs.sv`, `rtl/mem/dpram.sv`,
  `rtl/pll/`, and the top-level `BreakThru.sv`.
- **Authorship:** original work of this project, implementing behavior derived
  from the MAME `brkthru` driver (`src/mame/dataeast/brkthru.cpp`).
- **License:** GPL-3.0, as part of the combined work.

---

## Stated changes (GPLv3 §5 disclosure)

The only modification to any vendored GPL-licensed file:

- **File:** `rtl/sound/jt12/jt12_top.v`
- **Change:** The unconditional `assign fm_snd_left/right = accum_l/r[...]`
  (YM2612 accumulator sum) was moved inside a `generate if (use_pcm==1)` block.
  In this older jt12 copy it collided with the YM2203 accumulator branch
  (`gen_2203_acc`, which drives `fm_snd_* = mono_snd`), causing a Quartus
  multiple-constant-drivers error for the `jt03` (`use_pcm==0`) configuration.
- **Effect:** Resolves the multiple-driver conflict for the YM2203 build path;
  YM2612 behavior is unchanged.
- **Marking:** The edit is tagged in-file with a `BreakThru_MiSTer fix:` comment.
- **Reference:** `rtl/sound/NOTICE.md`.

---

## No game ROMs

This core and repository contain **no** Break Thru ROM data or extracted game
assets. Break Thru / *Kyohkoh-Toppa* is © 1986 Data East. ROMs are loaded at
runtime from a user-supplied `brkthru.zip` via the MRA and are not redistributed
here.
