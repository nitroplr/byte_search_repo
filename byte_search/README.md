# byte_search

Fast byte-level searching utilities for `Uint8List`.

Designed for workloads like log parsing and binary scanning where you do
**millions of searches** and most are **rejects**.

## Features

- `BytePattern`: Horspool-based byte matcher optimized for high-reject workloads
    - no string allocation
    - no allocations per search
    - supports slice searching with `start` / `end`
- `ByteSet`: precompiled 256-byte membership table for O(1) byte classification
- Utilities: `indexOfByte`, `indexOfAnyByte`, `startsWithBytes`, `endsWithBytes`

## Example

```dart
final pattern = BytePattern.fromAscii(' was given to ');
final bracket = ByteSet.single(']'.codeUnitAt(0));

int messageStart(Uint8List line) {
  // App-specific: skip prefix up to ']'
  final idx = indexOfAnyByte(
    line,
    bracket,
    end: line.length < 64 ? line.length : 64,
  );
  if (idx == -1) return 0;

  int s = idx + 1;
  if (s < line.length && line[s] == ' '.codeUnitAt(0)) s++;
  return s;
}

bool interesting(Uint8List line) {
  final start = messageStart(line);
  return pattern.hasMatch(line, start: start);
}
```

## Performance

`BytePattern` is designed for cases where matches are rare.
It reduces constant factors by avoiding unnecessary comparisons and
does not allocate during search, making it suitable for streaming
and large-file parsing.