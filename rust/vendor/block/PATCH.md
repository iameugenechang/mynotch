# Local block 0.1.6 compatibility patch

Source: the published `block` 0.1.6 crate by Steven Sheldon, https://github.com/SSheldon/rust-block. The registry archive checksum is `0d8c1fef690941d3e7788d328517591fecc684c084084702d6ff1641e993699a`.

Copied on 2026-11-05. Upstream declares MIT licensing in `Cargo.toml`; its published archive contains no separate license text. The original manifest is retained as `Cargo.upstream.toml`, along with the original README and test source. This patch is selected through the root `[patch.crates-io]`, not a Cargo-cache edit.

## Changes

- Replace the uninhabited empty `Class` enum with a private C-layout struct containing 32 pointer slots. Apple's SDK `usr/include/Block.h` declares `_NSConcreteStackBlock` as `void *[32]`. The block header still holds one pointer to this class object, so the header layout is unchanged.
- Use `ptr::addr_of!` to take the symbol's address without constructing a Rust reference. No class bytes are read or written.
- Spell the previously implicit C ABI as `extern "C"`. This preserves the calling convention and fixes the `missing_abi` warnings exposed when compiling the crate locally.
- Remove the dev-dependency on the upstream `test_utils` path, which is absent from the published archive. Disable that crate's unit-test target; the sources remain for reference. Runtime regression checks run through anotchup's headless native executable instead. The compatibility lint is denied, not suppressed.

## Evidence

The original source fails a direct `rustc -D uninhabited_static` compile. The patched production source passes `rustc -D warnings`, outside Cargo's dependency lint cap. `rust/verify.sh` repeats that check and requires exactly one locally patched `block` dependency.

`--check-native` exercises stack invocation, native `_Block_copy`, retaining/releasing heap blocks, invocation after the original reference is released, and exactly-once destruction of a captured resource. The full application dependency build and Clippy checks pass without the prior warnings. No GUI, camera, or permission prompt is involved.

This is a narrow compatibility patch, not a safety audit of the entire legacy crate or its non-Apple runtimes. A future move to block2 belongs with an upstream API migration, not a package rename pretending to be ABI-compatible.
