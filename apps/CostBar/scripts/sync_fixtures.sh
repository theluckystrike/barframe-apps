#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p Sources/CostBarApp/Fixtures
cp Tests/CostBarCoreTests/Fixtures/* Sources/CostBarApp/Fixtures/
