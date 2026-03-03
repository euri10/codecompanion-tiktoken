#!/usr/bin/env bash
set -e

echo "Building Rust library..."
cargo build --release

LIB_NAME="tiktoken"   # change if needed
TARGET_DIR="target/release"
LUA_DIR="lua"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  cp "$TARGET_DIR/lib${LIB_NAME}.dylib" "$LUA_DIR/${LIB_NAME}.so"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  cp "$TARGET_DIR/lib${LIB_NAME}.so" "$LUA_DIR/${LIB_NAME}.so"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win32" ]]; then
  cp "$TARGET_DIR/${LIB_NAME}.dll" "$LUA_DIR/${LIB_NAME}.dll"
fi

echo "Build complete."

