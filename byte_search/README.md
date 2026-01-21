# byte_search

High-performance byte searching utilities for `Uint8List`.

This package provides **low-allocation primitives** for searching and scanning
byte data without converting to `String`.

It is designed for performance-critical workloads such as log parsing,
binary protocol processing, and large file scanning—especially when you perform
**millions of searches** and most are **rejects**.

## Related packages

- [`byte_search_io`](https://pub.dev/packages/byte_search_io): disk-backed scanning utilities built on `RandomAccessFile`
  (chunked reading, record extraction, and binary search over sorted files).
- `byte_search_io` **re-exports `byte_search`**, so for file-based workflows you can use a single import:
  `import 'package:byte_search_io/byte_search_io.dart';`
  *(Requires `dart:io`, so it does not work on the web.)*

---

## Features

### `BytePattern`

A reusable, Horspool-style compiled byte matcher optimized for high-reject workloads.

- no string allocation
- no allocations on the hot path
- supports searching within a slice via `start` / `end`
- immutable and reusable across searches

### `ByteSet`

A precompiled 256-entry lookup table for constant-time byte classification.

- `O(1)` membership checks
- useful for delimiter detection and byte-class scanning

### Uint8List extensions

Low-level helpers exposed as extension methods on `Uint8List`:

- `Uint8List.indexOfByte`
- `Uint8List.indexOfAnyByte`
- `Uint8List.indexOfByteNotIn`
- `Uint8List.startsWithBytes`
- `Uint8List.endsWithBytes`
- `Uint8List.containsInOrder`
- `Uint8List.subView`

All APIs operate directly on `Uint8List` via extension methods and are
allocation-free on the hot path.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  byte_search: ^0.1.0
