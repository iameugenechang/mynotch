#!/bin/bash
# Builds the SwiftUI twin next to the Rust probe's build output. usage: build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")"
profile="${1:-release}"; out="../target/twin-$profile"; mkdir -p "$out"
flags=(-swift-version 5 -target arm64-apple-macosx14.0 -framework AppKit -framework SwiftUI -framework CoreVideo)
[ "$profile" = release ] && flags+=(-O) || flags+=(-Onone -g)
swiftc "${flags[@]}" -o "$out/anotchup-twin" Twin.swift
echo "$out/anotchup-twin"
