/// Debug-only range validation for byte_search internals.
///
/// Throws [RangeError] **only when asserts are enabled** (debug/test).
/// In release/profile this is a no-op.
@pragma('vm:prefer-inline')
void checkRange(int start, int end, int length) {
  assert(() {
    if (start < 0 || start > length) throw RangeError.range(start, 0, length, 'start');
    if (end < 0 || end > length) throw RangeError.range(end, 0, length, 'end');
    if (start > end) throw RangeError('Invalid range: start=$start > end=$end');
    return true;
  }());
}