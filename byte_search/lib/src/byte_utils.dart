import 'dart:typed_data';

import 'byte_set.dart';

/// Finds the first occurrence of [value] in [bytes] between [start] (inclusive)
/// and [end] (exclusive). Returns -1 if not found.
@pragma('vm:prefer-inline')
int indexOfByte({required Uint8List bytes, required int value, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  final int v = value & 0xFF;
  for (int i = start; i < e; i++) {
    if (bytes[i] == v) return i;
  }
  return -1;
}

/// Finds the first byte in [bytes] that is contained in [set] between [start]
/// (inclusive) and [end] (exclusive). Returns -1 if not found.
@pragma('vm:prefer-inline')
int indexOfAnyByte({required Uint8List bytes, required ByteSet set, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  for (int i = start; i < e; i++) {
    if (set.contains(bytes[i])) return i;
  }
  return -1;
}

/// Finds the first byte in [bytes] that is NOT contained in [set] between [start]
/// (inclusive) and [end] (exclusive). Returns -1 if not found.
@pragma('vm:prefer-inline')
int indexOfByteNotIn({required Uint8List bytes, required ByteSet set, int start = 0, int? end}) {
  final int e = end ?? bytes.length;
  for (int i = start; i < e; i++) {
    if (!set.contains(bytes[i])) return i;
  }
  return -1;
}

/// Returns true if [bytes] starts with [prefix] within [start]..[end).
bool startsWithBytes({
  required Uint8List bytes,
  required Uint8List prefix,
  int start = 0,
  int? end,
}) {
  final int e = end ?? bytes.length;
  if (prefix.isEmpty) return true;
  if (e - start < prefix.length) return false;

  for (int i = 0; i < prefix.length; i++) {
    if (bytes[start + i] != prefix[i]) return false;
  }
  return true;
}

/// Returns true if [bytes] ends with [suffix] within [start]..[end).
bool endsWithBytes({
  required Uint8List bytes,
  required Uint8List suffix,
  int start = 0,
  int? end,
}) {
  final int e = end ?? bytes.length;
  if (suffix.isEmpty) return true;
  final int n = e - start;
  if (n < suffix.length) return false;

  final int s = e - suffix.length;
  for (int i = 0; i < suffix.length; i++) {
    if (bytes[s + i] != suffix[i]) return false;
  }
  return true;
}
