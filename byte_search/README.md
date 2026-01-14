# byte_search

High-performance byte searching utilities for `Uint8List`.

This package provides **low-allocation primitives** for searching and scanning
byte data without converting to `String`.

It is designed for performance-critical workloads such as log parsing,
binary protocol processing, and large file scanning—especially when you perform
**millions of searches** and most are **rejects**.

See also: [`byte_search_io`](https://pub.dev/packages/byte_search_io) for
disk-backed file navigation, chunked reading, record extraction, and
binary search over large, delimiter-separated files.

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

### Utilities
Low-level helpers for common byte-scanning tasks:

- `indexOfByte`
- `indexOfAnyByte`
- `indexOfByteNotIn`
- `startsWithBytes`
- `endsWithBytes`

All APIs operate directly on `Uint8List` and are allocation-free on the hot path.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  byte_search: ^0.1.0
```

## Example

```dart
final pattern = BytePattern.fromAscii(needle: ' was given to ');
final bracket = ByteSet.single(']'.codeUnitAt(0));

int messageStart(Uint8List line) {
  // App-specific: skip prefix up to ']'
  final idx = indexOfAnyByte(
    bytes: line,
    set: bracket,
    end: line.length < 64 ? line.length : 64,
  );
  if (idx == -1) return 0;

  int s = idx + 1;
  if (s < line.length && line[s] == ' '.codeUnitAt(0)) s++;
  return s;
}

bool interesting(Uint8List line) {
  final start = messageStart(line);
  return pattern.hasMatch(haystack: line, start: start);
}
```

## Design goals

`byte_search` is intentionally designed with a narrow focus. Its goals are:

- **Operate directly on bytes**  
  All APIs work on `Uint8List` and avoid `String` conversion or text processing.

- **Avoid allocations on hot paths**  
  Once constructed, core primitives perform searches and checks without allocating.

- **Favor predictable, low constant factors**  
  The implementation prioritizes simple, well-understood algorithms and fast
  rejection over complex heuristics.

- **Support reuse and composability**  
  Compiled patterns and sets are immutable and designed to be reused across
  many searches.

- **Expose low-level control**  
  APIs make start/end ranges and byte-level behavior explicit, allowing callers
  to tune scanning logic for their specific data formats.

## Performance

`byte_search` is optimized for workloads where byte-level scanning is on the
critical path.

Key performance characteristics:

- **No string allocation**  
  All APIs operate directly on `Uint8List` data and avoid converting to `String`.

- **Allocation-free hot paths**  
  Once constructed, `BytePattern` and `ByteSet` do not allocate during search
  or membership checks.

- **Optimized for high-reject searches**  
  `BytePattern` uses a Horspool-style algorithm with fast-reject checks, making
  it well-suited for cases where most scans do *not* produce a match.

- **Reusable compiled state**  
  Patterns and sets are immutable and designed to be reused across many searches,
  amortizing setup costs over time.

This package focuses on reducing constant factors and avoiding unnecessary work
rather than providing asymptotically different algorithms. It is most effective
when scanning large volumes of data or performing millions of repeated searches.

## When NOT to use this package

`byte_search` is intentionally low-level and optimized for specific workloads.
It may not be the right choice in the following situations:

- **You already have `String` data**  
  If your input is already a `String` and performance is not critical, Dart’s
  built-in `String` methods (`contains`, `indexOf`, regular expressions, etc.)
  are usually simpler and sufficient.

- **You only perform a small number of searches**  
  The benefits of `BytePattern` come from reusing a compiled pattern across many
  searches. For one-off or infrequent searches, simpler approaches may be clearer.

- **Matches are frequent and most data is accepted**  
  `BytePattern` is optimized for *high-reject* workloads. If nearly every scan
  results in a match, the advantages over simpler scans may be smaller.

- **You need full Unicode or locale-aware text processing**  
  This package operates on raw bytes (`Uint8List`) and does not understand
  Unicode grapheme clusters, normalization, or locale-specific rules.

- **Code clarity is more important than raw throughput**  
  These APIs expose low-level concepts such as byte ranges, start/end indices,
  and precompiled tables. For non-performance-critical paths, higher-level APIs
  may be easier to read and maintain.

## License

BSD 3-Clause (see `LICENSE`).