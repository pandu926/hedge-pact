#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
forge build --root "$PROJECT_ROOT/contracts"
cd "$PROJECT_ROOT/vendor/gmx"
export NODE_OPTIONS=--max-old-space-size=6144
./node_modules/.bin/hardhat compile
./node_modules/.bin/hardhat test --no-compile "$PROJECT_ROOT/gmx/test/ShortAdl.ts" "$PROJECT_ROOT/gmx/test/Integration.ts"
