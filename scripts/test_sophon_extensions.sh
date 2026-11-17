#!/usr/bin/env bash
# Build in a new directory; retain logs and binaries for inspection.
set -eo pipefail
source /opt/eda/eda.bashrc
source /opt/rh/devtoolset-11/enable
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d /tmp/croc-sophon-extensions.XXXXXX)
prefix=riscv-nuclei-elf-
if [[ -v RISCV_PREFIX ]]; then prefix=$RISCV_PREFIX; fi
cc="$prefix"gcc
objcopy="$prefix"objcopy
objdump="$prefix"objdump
bender=/home/yangfei/.cargo/bin/bender
if [[ -v BENDER ]]; then bender=$BENDER; fi
command -v vcs
command -v "$cc"
echo "Results: $out"

for smoke in 0 1; do
  "$cc" -march=rv32i -mabi=ilp32 -mcmodel=medany -nostdlib \
    -DSOC_SMOKE="$smoke" -Wl,--no-relax -T "$root/sw/link.ld" \
    "$root/sw/test/sophon_extensions/start.S" -o "$out/extensions_$smoke.elf"
  "$objcopy" -O verilog "$out/extensions_$smoke.elf" "$out/extensions_$smoke.hex"
  "$objdump" -d "$out/extensions_$smoke.elf" > "$out/extensions_$smoke.dump"
done
cd "$root"
"$bender" script vcs -t rtl -t simulation -t verilator \
  -D SYNTHESIS -D SIMULATION > "$out/compile.sh"
sed -i 's/\bvlogan\b/vlogan -timescale=1ns\/1ps/; s/\bvcs\b/vcs -timescale=1ns\/1ps/' "$out/compile.sh"
cd "$out"
timeout 600 bash "$out/compile.sh" > "$out/analyze.log" 2>&1
timeout 600 vlogan -full64 -sverilog -timescale=1ns/1ps \
  "$root/rtl/test/tb_sophon_extensions.sv" >> "$out/analyze.log" 2>&1
timeout 600 vcs -full64 -timescale=1ns/1ps -j4 -o "$out/core_sim" \
  tb_sophon_extensions > "$out/core_build.log" 2>&1
for delay in 0 3 7; do
  timeout 900 "$out/core_sim" -no_save +vcs+flush+all \
    +binary="$out/extensions_0.hex" +wait_cycles="$delay" \
    > "$out/core_wait_$delay.log" 2>&1
  rg 'SOPHON EXTENSIONS PASS' "$out/core_wait_$delay.log"
done
timeout 900 "$out/core_sim" -no_save +vcs+flush+all \
  +binary="$out/extensions_0.hex" +wait_cycles=3 +reset_mid \
  > "$out/core_reset.log" 2>&1
rg 'SOPHON EXTENSIONS PASS' "$out/core_reset.log"

timeout 600 vcs -full64 -timescale=1ns/1ps -j4 -o "$out/soc_sim" \
  tb_croc_soc > "$out/soc_build.log" 2>&1
make -C "$root/sw" RISCV_PREFIX="$prefix" RISCV_MARCH=rv32i \
  BUILDDIR="$out/sw/build" BINDIR="$out/sw/bin" \
  "$out/sw/bin/helloworld.hex" "$out/sw/bin/test/soc_demo.hex" \
  > "$out/software_build.log" 2>&1
for program in "$out/extensions_1.hex" "$out/sw/bin/helloworld.hex" \
               "$out/sw/bin/test/soc_demo.hex"; do
  name=$(basename "$program" .hex)
  timeout 900 "$out/soc_sim" -no_save +vcs+flush+all +binary="$program" \
    > "$out/soc_$name.log" 2>&1
  rg 'Simulation finished: SUCCESS' "$out/soc_$name.log"
done
echo "All Sophon extension tests passed: $out"
