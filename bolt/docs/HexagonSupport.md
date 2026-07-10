# BOLT Support for Hexagon

This page documents the current state of BOLT's Hexagon target support:
how to build a Hexagon binary that BOLT can process, known limitations,
and the tooling available for gathering execution profiles (for both
profile-guided function reordering and [heatmaps](Heatmaps.md)).

## Overview

Hexagon is a VLIW architecture where multiple instructions are grouped
into fixed-boundary packets. BOLT's Hexagon support covers:

- Disassembly and packet-boundary-aware re-emission of VLIW bundles.
- Hexagon-specific MC relocations (`R_HEX_B22_PCREL`, `R_HEX_32_6_X`, etc.).
- Hardware loop (`loop0`/`loop1`/`endloop0`/`endloop1`) relocation and
  splitting, including branch relaxation when a hardware loop body is
  split across the loop boundary.
- Basic unreachable code elimination and block/function
  reordering - note limitations below.

HVX (vector coprocessor) instructions are **not** currently handled
by BOLT's Hexagon backend. Binaries containing HVX code sections can
still be processed if BOLT is restricted to specific functions
but a function containing HVX instructions will fail to disassemble.

## Building a binary BOLT can process

Two toolchain combinations have been validated on Hexagon:

### Upstream clang + ld.lld (recommended)

```bash
obj_claude/bin/clang --target=hexagon-unknown-elf -mv73 -O2 \
    -ffunction-sections -c input.c -o input.o

obj_claude/bin/ld.lld input.o -o input.elf --emit-relocs -e main

obj_claude/bin/llvm-bolt input.elf -o input.bolt.elf
```

This path is fully supported end-to-end: compile, link, and BOLT
processing all work.

### Hexagon SDK

```bash
hexagon-clang -mv73 -O2 -ffunction-sections \
    -Wl,--emit-relocs -o input.elf input.c

# hexagon-link emits a malformed .note.llvm.cgmdinfo note that BOLT
# cannot parse; strip it first.
obj_claude/bin/llvm-objcopy --remove-section=.note.llvm.cgmdinfo input.elf

obj_claude/bin/llvm-bolt input.elf -o input.bolt.elf
```

This path produces a binary with a working CRT that can run under
`hexagon-sim`, but only works if the input avoids GP-relative
relocations (see below). Compiling with `-G0` (no small-data section)
avoids `R_HEX_GPREL16_*` relocations from vendor CRT/libc objects.

## Known limitations

- **GP-rel relocations**: `R_HEX_GPREL16_0/1/2/3` (small-data
  addressing) are not implemented in either `ld.lld`'s Hexagon backend
  or BOLT. Vendor `hexagon-link`-produced CRT and libc objects use
  GP-relative addressing by default; compiling with `-G0` avoids this,
  but pulls in a different (larger) CRT/libc variant from the SDK.
- **HVX disassembly**: Functions containing HVX instructions cannot be
  disassembled by BOLT today. Use `--funcs-file` to restrict processing
  to non-HVX functions, or use the standalone `hex-pctrace-to-fdata`
  ordering tool (below) to compute a function order without invoking
  BOLT's binary rewriting on HVX-containing binaries.
- **`.new`-value packet dependencies**: Hexagon packets can have
  producer/consumer dependencies between instructions within the same
  packet (`.new` values, e.g. a store using the just-computed value of
  a compare in the same packet). Block reordering within a function can
  separate a `.new` producer from its consumer if the reordering pass
  is not aware of intra-packet dependencies, corrupting the packet. This
  primarily affects `--reorder-blocks`; function-level reordering is not
  affected, since whole functions (and their packets) move as a unit.
- **Address-0 / `.start` section binaries**: bare-metal binaries with
  code starting at address 0 (common in `hexagon-sim` standalone
  binaries) can hit a "failed to extract relocated value" assertion in
  `analyzeRelocation` when relocations reference symbols at address 0.
- **TLB mapping for relocated code**: BOLT places new/hot code at a high
  address (around `0x400000` by default). Bare-metal Hexagon runtimes
  that rely on a fixed CRT-managed TLB mapping may fault when code is
  placed outside the mapped range; either adjust the TLB setup or use
  `--hot-functions-at-end=false`-style layout constraints appropriate to
  the target runtime.

## Profile collection

If you're using linux on hexagon, the usual `perf record` / `perf2bolt`
path ([Heatmaps.md](Heatmaps.md)) is available. But for everyone
else, there's other tools to consider, both converting into formats BOLT
already understands -- `fdata` for `--reorder-functions`, or the `-pa`
pre-aggregated sample format for `llvm-bolt` and `llvm-bolt-heatmap`.
Pick whichever execution environment you already have:

|                        | `hex-pctrace-to-fdata`                | `qemu-profiling`                          |
|------------------------|----------------------------------------|--------------------------------------------|
| Execution environment  | `hexagon-sim`                          | `qemu-hexagon` / `qemu-system-hexagon`     |
| Input                  | `--pctrace_nano` PC trace              | TCG plugin (`libtcg_prof.so`)              |
| Output format          | `fdata` (edge counts) or a computed function order | `-pa` pre-aggregated `B`/`F`/`E` records |
| Function reordering    | Yes (`hex-pctrace-to-fdata order`, or feed `fdata` straight to `llvm-bolt -data`) | Yes (`tcg-prof-convert bolt`, feed to `llvm-bolt -pa -perfdata=`) |
| `llvm-bolt-heatmap`    | Not currently -- `llvm-bolt-heatmap` reads perf-style samples (`-pa`/perf.data/perfscript), not the already-aggregated `fdata` format `hex-pctrace-to-fdata` emits | Yes -- its `-pa` output is exactly what `llvm-bolt-heatmap -pa -perfdata=` expects |

### hexagon-sim PC tracing (`hex-pctrace-to-fdata`)

A standalone Rust tool at `bolt/utils/hexagon/hex-pctrace-to-fdata/`
that converts `hexagon-sim --pctrace_nano` traces into BOLT's `fdata`
profile format, and can compute an HFSort-style function order from the
resulting profile. This is the tool to reach for when BOLT itself
cannot rewrite the binary (HVX-containing functions cannot be
disassembled -- see limitations above) or when you want to reorder at
the source/link level instead of rewriting the binary in place.

1. Run the target binary under `hexagon-sim` with PC tracing enabled:

   ```bash
   hexagon-sim -mv73 --pctrace_nano trace.txt input.elf
   ```

2. Convert the trace to BOLT's `fdata` profile format:

   ```bash
   hex-pctrace-to-fdata fdata --binary input.elf --trace trace.txt \
       --output input.fdata
   ```

3. Either feed `input.fdata` to `llvm-bolt -data input.fdata
   --reorder-functions=cdsort` directly (non-HVX binaries), or compute a
   standalone function order with HFSort-style call graph clustering:

   ```bash
   hex-pctrace-to-fdata order --fdata input.fdata --output order.txt
   ```

   `order.txt` can then be applied via source-level reordering (regenerate
   the source with functions defined in the computed order) or via
   `ld.lld --symbol-ordering-file=order.txt` at link time.

The tool also has a `reorder` subcommand that directly permutes function
bodies in an ELF binary's `.text` section. It only updates the symbol
table, not PC-relative call instructions, so it does not produce a
runnable binary -- it exists for inspecting layout, not for production
use. Prefer source-level or link-time reordering to actually apply a
computed order.

#### Measuring I-cache impact

`hex-pctrace-to-fdata` only builds the branch-frequency profile used to
drive reordering; it does not report cache statistics. To measure the
actual I-cache impact of a given layout, run the binary under
`hexagon-sim --timing` with PMU counters enabled and diff the counters
before/after BOLT:

```bash
hexagon-sim -mv73na_1 --timing --quiet --pmu_statsfile baseline_pmu.txt input.elf
hexagon-sim -mv73na_1 --timing --quiet --pmu_statsfile bolt_pmu.txt input.bolt.elf
```

The relevant counters are `ICACHE_DEMAND_MISS` (I-cache misses) and
`IU_NO_PKT_PVIEW_CYCLES` (cycles stalled on I-cache), which can be
diffed directly out of the two `pmu_statsfile` outputs.

### QEMU TCG plugin (`qemu-profiling`)

A QEMU TCG plugin and profile converter (Rust; `qemu-profiling` in
Qualcomm's QEMU fork) that instruments every translation block at JIT
compile time and, unlike `hex-pctrace-to-fdata`, needs no target
simulator license -- it runs under `qemu-hexagon` (linux-user) or
`qemu-system-hexagon`. It is architecture-generic (Hexagon, RISC-V,
AArch64, ...), so the same plugin works across targets.

```bash
cd qemu-profiling
cargo build --release -p qemu-pgo-plugin -p tcg-prof-convert
```

Profile a run (`tier=edges` records taken branches and fall-throughs --
the level BOLT and the heatmap both need):

```bash
qemu-hexagon -plugin target/release/libtcg_prof.so,tier=edges,output=profile.pgo \
    input.elf
```

Convert to BOLT's pre-aggregated format and use it either for
optimization or for a heatmap:

```bash
tcg-prof-convert bolt -i profile.pgo -b input.elf -o bolt.txt

# Function reordering:
llvm-bolt input.elf -o input.bolt.elf -pa -p bolt.txt --reorder-functions=cdsort

# Heatmap:
llvm-bolt-heatmap input.elf -pa -perfdata=bolt.txt -o heatmap.out
```

`qemu-hexagon` requires a Linux (not bare-metal) Hexagon binary --
compile with `--target=hexagon-unknown-linux-musl`. Static-PIE binaries
(the default with `-static` alone) are not handled correctly by
`qemu-hexagon`'s loader; add `-static -no-pie` explicitly.
