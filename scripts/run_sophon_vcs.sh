#!/usr/bin/env bash
# Build and run the Sophon-on-Croc VCS regression with reproducible options.
set -euo pipefail

usage() {
  echo "Usage: $0 [--build] <program.hex>"
  echo "  --build  Rebuild the VCS simulator before running."
}

build=0
if [[ ${1:-} == "--build" ]]; then
  build=1
  shift
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hex=$(realpath "$1")
out_dir=${CROC_SOPHON_VCS_OUT:-/tmp/croc-sophon-vcs}
simv="$out_dir/simv_sophon"
log="$out_dir/$(basename "${hex%.hex}").log"

mkdir -p "$out_dir"

if [[ $build -eq 1 || ! -x $simv ]]; then
  # The site EDA setup script reads LD_LIBRARY_PATH even when it is unset.
  set +u
  source /opt/eda/eda.bashrc
  source /opt/rh/devtoolset-11/enable
  set -u

  script=$(mktemp /tmp/croc-sophon-vcs.XXXXXX.sh)
  trap 'rm -f "$script"' EXIT

  cd "$root"
  /home/yangfei/.cargo/bin/bender script vcs -t rtl -t simulation -t verilator \
    -D SYNTHESIS -D SIMULATION > "$script"
  sed -i 's/\bvlogan\b/vlogan -timescale=1ns\/1ps/; s/\bvcs\b/vcs -timescale=1ns\/1ps/' "$script"
  bash "$script"
  vcs -full64 -timescale=1ns/1ps -j8 -o "$simv" tb_croc_soc
fi

cd "$root"
"$simv" -no_save +vcs+flush+all +binary="$hex" |& tee "$log"
