#!/usr/bin/env bash
# Decides which platform jobs CI needs for a change.
#
# Reads the changed file paths on stdin, one per line, and prints lines for
# $GITHUB_OUTPUT:
#   android|darwin|windows|linux|web=true|false
#   integration=<JSON list of integration test targets>
# A path it doesn't know runs everything. With --all, everything runs.
#
# Try it locally:
#   git diff --name-only origin/main... | bash tool/ci_changes.sh
set -euo pipefail

all=false android=false darwin=false windows=false linux=false web=false
[ "${1:-}" = --all ] && all=true

if ! $all; then
  while IFS= read -r path; do
    case "$path" in
      '') ;;
      # Covered by the analyze & test and pub.dev score jobs, which always run.
      *.md | LICENSE | .gitignore | .github/ISSUE_TEMPLATE/* | .github/pull_request_template.md) ;;
      test/io/windows_test.dart | test/io/src/*) windows=true ;;
      test/*) ;;
      android/* | lib/src/platforms/android/* | example/android/* | tool/jnigen.dart | tool/check_jni_keeps.dart) android=true ;;
      darwin/* | lib/src/platforms/darwin/* | example/ios/* | example/macos/* | tool/ffigen.dart) darwin=true ;;
      lib/src/platforms/windows/* | example/windows/*) windows=true ;;
      lib/src/platforms/linux/* | example/linux/*) linux=true ;;
      lib/src/platforms/io_entries.dart) windows=true linux=true ;;
      lib/src/platforms/web/* | example/web/*) web=true ;;
      # Shared Dart code, the example app, pubspec, CI itself, anything new.
      *) all=true ;;
    esac
  done
fi

if $all; then
  android=true darwin=true windows=true linux=true web=true
fi

# Integration tests run listEntries through the native code of each target.
targets=()
$darwin && targets+=('{"target":"macOS","os":"macos-latest"}')
$linux && targets+=('{"target":"Linux","os":"ubuntu-latest"}')
$windows && targets+=('{"target":"Windows","os":"windows-latest"}')

echo "android=$android"
echo "darwin=$darwin"
echo "windows=$windows"
echo "linux=$linux"
echo "web=$web"
echo "integration=[$(IFS=,; echo "${targets[*]:-}")]"
