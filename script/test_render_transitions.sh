#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d)
swiftc -parse-as-library -O \
  "$PROJECT_DIR/Sources/GlassRenderer.swift" \
  "$PROJECT_DIR/Tests/RenderTransitionTests.swift" \
  -framework AppKit -framework SwiftUI -framework MetalKit -framework CoreVideo \
  -o "$TEST_DIR/render-transition-tests"
"$TEST_DIR/render-transition-tests"
