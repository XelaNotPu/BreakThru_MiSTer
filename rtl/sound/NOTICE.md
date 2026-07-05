# Vendored sound cores — provenance (all GPLv3, Jose Tejada / @topapate)

Used at M10 (sound). Licenses preserved in each subdirectory.

- **jt12/** — YM2203 (`jt03`) + jt12 support files. `jt03.v` exposes `fm_snd`
  (signed 16) and `psg_snd` (unsigned 10) on separate buses → maps to MAME's 0.10 FM / 0.50 SSG mix.
- **jt49/** — SSG/AY block required by `jt03`. Cloned from https://github.com/jotego/jt49 (GPLv3).
- **jtopl/** — YM3526 (OPL). Cloned from https://github.com/jotego/jtopl (GPLv3). Use module `jtopl`
  (NOT `jtopl2`=YM3812 / `jt2413`/`jtopll_*`=OPLL). Single signed-16 `snd` out, `irq_n`.

Modifications:
- `jt12/jt12_top.v`: ONE minimal bug-fix — the unconditional `assign fm_snd_left/right =
  accum_l/r[...]` (YM2612 accumulator sum) is now gated inside a `generate if(use_pcm==1)` block.
  In this older MegaPlay jt12 copy it collided with the YM2203 branch (`gen_2203_acc`, which drives
  `fm_snd_* = mono_snd`), causing a Quartus multiple-constant-drivers error for jt03 (use_pcm==0).
  The fix is marked with a `BreakThru_MiSTer fix:` comment in the file. Behavior for YM2612 unchanged.
- All other files copied verbatim. These make the project's overall license GPLv3.
Wiring model: `jtbubl_sound.v` (jt03 + plain jtopl, the same chip pair) in the jtcores tree.
