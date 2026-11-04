#!/bin/bash
set -euo pipefail
appdir="$(cd "$(dirname "$0")/.." && pwd)"
bash "$appdir/../../kit/make_app.sh" "$appdir"
