#!/usr/bin/env bash
# Archive the results/ directory into archives/results-<timestamp>.tar.gz
# Run on the host after the exam to collect all student work.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p archives
stamp="$(date +%Y%m%d-%H%M%S)"
tar czf "archives/results-${stamp}.tar.gz" results
echo "Wrote archives/results-${stamp}.tar.gz"
