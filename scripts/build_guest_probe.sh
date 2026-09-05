#!/bin/bash
# Replicate risc0_build's cargo invocation to see real guest compile errors.
set -u
cd /home/test/zkstark
unset RUSTUP_TOOLCHAIN
export RUSTC=/home/test/.risc0/toolchains/v1.97.0-rust-x86_64-unknown-linux-gnu/bin/rustc
export RUSTDOC=/home/test/.risc0/toolchains/v1.97.0-rust-x86_64-unknown-linux-gnu/bin/rustdoc
export CC=/home/test/.risc0/toolchains/v1.97.0-rust-x86_64-unknown-linux-gnu/bin/riscv32-unknown-elf-gcc
export CFLAGS_riscv32im_risc0_zkvm_elf="-march=rv32im -nostdlib"
S="$(printf '\x1f')"
RFLAGS="-C${S}passes=lower-atomic${S}-C${S}link-arg=-Ttext=0x00200800${S}-C${S}link-arg=--fatal-warnings${S}-C${S}panic=abort${S}--cfg${S}getrandom_backend=\"custom\""
export CARGO_ENCODED_RUSTFLAGS=$(printf '%s' "$RFLAGS")
cargo build --manifest-path /home/test/zkstark/methods/guest/Cargo.toml \
    --target riscv32im-risc0-zkvm-elf --release --target-dir /tmp/guesttest \
    > /mnt/d/lair/zkstark/scripts/gg2.txt 2>&1
echo "EXIT=$?"