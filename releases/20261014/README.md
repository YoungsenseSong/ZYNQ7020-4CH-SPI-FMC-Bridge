# Current FPGA Projects

- `single_channel_demo/`: SPI record/block path with three-wire GPIO CSR,
  retained bit/ltx and 448-bit ILA.
- `single_channel_fmc/`: latest unchanged real FMC/CSR/USB companion design,
  retained bit/ltx and 448-bit ILA.
- `dual_channel/`: MC008 complete two-channel board wrapper, FMC/CSR,
  BRAM buffering, 288-bit ILA and constraints.
- `four_channel/`: corresponding MC008 complete four-channel design.

Single-channel `BUILD_FPGA.tcl` builds into a separate output directory;
`CREATE_FPGA.tcl` recreates the supplied XPR after removing an old XPR.
Dual/four creation/build scripts are in `scripts/`.

All four tops elaborate with Icarus. GPIO-serial transaction/full-core models
and formal FMC digital models pass. The common multichannel core tests
exercise mux/FIFO/dual-bank storage/capture/block ACK. These are digital-model
results, not board validation.

Dual/four synthesis and ILA passed in the earlier MC008 round, but CH1 and
CH1-CH3 package pins are not frozen. Implementation and bitstream remain
intentionally blocked. No physical pins were guessed.

Formal FMC hardware is not claimed working. Existing untracked legacy
sources remain untouched; current releases are added independently.
