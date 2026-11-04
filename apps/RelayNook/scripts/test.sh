#!/bin/bash
set -euo pipefail
appdir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$appdir"
bash ../../kit/swift_test.sh
