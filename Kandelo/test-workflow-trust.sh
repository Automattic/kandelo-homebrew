#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT

# Keep this wrapper as a single fail-closed handoff to the retired-state parser.
exec ruby "$ROOT/Kandelo/test-workflow-trust.rb"
