# byte_search_io

Low-allocation building blocks for working with **large, delimiter-separated files** using `RandomAccessFile`.

This package is meant to be the “disk-first” layer for workflows like:

- reading **records (lines)** without loading the full file
- scanning a **byte range** efficiently
- doing a **binary search** over a **sorted** file to find `[start, end)` offsets, then scanning only that window

> If you’re parsing huge log files, this is the package that lets you jump to the right part of the file and read just what you need.

>  ⚠️ This package requires `dart:io` and is not supported on the web.

> See also: [`byte_search`](https://pub.dev/packages/byte_search), which is
> re-exported by this package and provides high-performance, allocation-free
> byte searching primitives that can be applied within records or chunks.

## Which package should I import?

- If you only have bytes in memory (`Uint8List`) → use `byte_search`.
- If you’re working with large files (`RandomAccessFile`) → use `byte_search_io`.

`byte_search_io` **re-exports** `byte_search`, so import one or the other.

---

## Features

### `RecordReader`
Read the **record containing an arbitrary byte offset** by scanning backward/forward to the nearest delimiters.

- delimiter-separated records (default: `\n`)
- CRLF-friendly via `trimCarriageReturn`
- bounded scanning via `maxBackwardScanBytes` / `maxForwardScanBytes`
- neighbor navigation:
    - `readRecordBeforeOffset(...)`
    - `readRecordAfterOffset(...)`

### `ChunkedFileReader`
Stream file data in chunks (optionally with overlap for raw scanning),
or stream **records** over a range (record-aware; no overlap required).

- `openRandomAccessFile(...)` → `Stream<ByteChunk>` (whole file)
- `openRandomAccessFileRange(...)` → `Stream<ByteChunk>` (`[start, end)` only)
- `openRandomAccessFileRecords(...)` → `Stream<RecordSlice>` (record-aware; no overlap required)

### `BinarySearchFile<K>`
Binary search a **sorted** delimiter-separated file to find offsets:

> The file must be sorted by key for all records where `parseKey` returns a non-null value.
> Records for which `parseKey` returns `null` are skipped during probing but must not
> violate the overall sort order.

- `lowerBound(...)` → first record with key `>= target`
- `upperBound(...)` → first record with key `> target`
- supports skipping unparseable records (`parseKey` returns `null`)
- throws `StateError` if a probe lands on a truncated record (increase `RecordReader` scan limits)

This is ideal for “timestamp-sorted logs”: binary search the time bounds, then scan only that subrange.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  byte_search_io: ^0.1.0
```

## Quick start: read a record at an offset
```dart
import 'dart:io';
import 'package:byte_search_io/byte_search_io.dart';

Future<void> main() async {
  final raf = await File('log.txt').open(mode: FileMode.read);

  final reader = RecordReader(); // newline-delimited by default
  final rec = await reader.readRecordContainingOffset(raf, 1 << 20);

  print(rec.toStringUtf8());
  await raf.close();
}
```

## Stream records (lines) without loading the file
```dart
import 'dart:io';
import 'package:byte_search_io/byte_search_io.dart';

Future<void> main() async {
  final raf = await File('log.txt').open(mode: FileMode.read);

  final recordReader = RecordReader(
    delimiter: 0x0A /* '\n' */,
    maxBackwardScanBytes: 1024 * 1024,
    maxForwardScanBytes: 1024 * 1024,
  );
  final chunked = ChunkedFileReader(closeRafOnDone: false);

  await for (final rec in chunked.openRandomAccessFileRecords(
    raf: raf,
    recordReader: recordReader,
    chunkSize: 1 << 22, // 4 MiB
  )) {
    // rec.bytes is the line (no '\n', and optionally no '\r')
    // rec.startOffset/endOffsetExclusive are absolute file offsets
    final line = rec.toStringUtf8(allowMalformed: true);
    // do something with line...
  }

  await raf.close();
}
```

## Binary search a sorted file, then scan just that range
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:byte_search_io/byte_search_io.dart';

DateTime? tryParseLogTime(Uint8List bytes) {
  // Example parser stub:
  // parse a timestamp prefix from bytes; return null if not present.
  // (Implement this for your log format.)
  return null;
}

Future<void> main() async {
  final raf = await File('sorted.log').open(mode: FileMode.read);

  final recordReader = RecordReader(
    delimiter: 0x0A /* '\n' */,
    maxBackwardScanBytes: 1024 * 1024,
    maxForwardScanBytes: 1024 * 1024,
  );

  final bs = BinarySearchFile<DateTime>(
    recordReader: recordReader,
    parseKey: (rec) => tryParseLogTime(rec.bytes),
    compare: (a, b) => a.compareTo(b),
  );

  final startTime = DateTime(2026, 1, 1, 0, 0, 0);
  final endTime = DateTime(2026, 1, 1, 1, 0, 0);

  final startOffset = await bs.lowerBound(raf: raf, target: startTime);
  final endOffset = await bs.upperBound(raf: raf, target: endTime);

  final chunked = ChunkedFileReader(closeRafOnDone: false);

  await for (final rec in chunked.openRandomAccessFileRecords(
    raf: raf,
    recordReader: recordReader,
    startOffset: startOffset,
    endOffsetExclusive: endOffset,
  )) {
    // process only records in [startTime, endTime]
  }

  await raf.close();
}
```

## Concepts
**Records and Delimiters**

A “record” is the bytes between delimiters. The delimiter byte is not included in `RecordSlice.bytes`.

For newline-delimited files:

- `delimiter`: `0x0A` (`\n`)
- if `trimCarriageReturn == true`, a trailing `\r` is removed (CRLF support)

**Sorted Files**

Records with `parseKey == null` may appear anywhere, but all parseable keys
must be in monotonic order for binary search to be correct.

**Offsets**

Offsets are absolute file byte offsets:

- `RecordSlice.startOffset` is inclusive
- `RecordSlice.endOffsetExclusive` is exclusive
- `ByteChunk.fileOffset` is the absolute offset where `bytes[0]` belongs

This lets you:

- seek back to exact positions
- slice ranges
- create reproducible “bookmarks” into huge files

**Truncation Flags**
- `BinarySearchFile` may throw `StateError` if a probe lands on a truncated record slice.
- Neighbor navigation may return `null` in truncation scenarios.

When scan limits are hit:

- `startTruncated == true` means the true record start was not found
- `endTruncated == true` means the true record end was not found

**Error Handling**

- Methods may throw `ArgumentError` / `StateError` for invalid parameters or oversized records.
- May rethrow I/O errors from `RandomAccessFile` operations or from `RecordReader`.

## Performance Notes

`byte_search_io` handles I/O, chunking, and record boundaries;
`byte_search` primitives can be applied within those records or chunks
to keep hot-path searching allocation-free.

`ChunkedFileReader.openRandomAccessFileRecords(...)` is record-aware and avoids overlap.

`ChunkedFileReader.openRandomAccessFile(...)` can use overlap for raw chunk scanning use-cases.

Both APIs allocate:

- per chunk (when yielding chunk bytes)
- per record (when yielding record bytes)

...but avoid per-byte allocations and avoid loading whole files.

## When to use what

- Need “the line around this offset”? → `RecordReader.readRecordContainingOffset`
- Need to stream lines/records? → `ChunkedFileReader.openRandomAccessFileRecords`
- Have a sorted file and want a time window fast? → `BinarySearchFile` + range record streaming

## When NOT to use this package

- **You already have the data in memory**  
  If your input is already a `Uint8List`, `byte_search` alone may be sufficient.

- **Files are small**  
  For small files, simpler APIs like `readAsLines()` may be clearer.

- **You need web support**  
  This package depends on `dart:io` and is not available on the web.

- **You want a full log parser**  
  This package provides navigation and record extraction, not domain-specific parsing.

## License

BSD 3-Clause (see `LICENSE`).
