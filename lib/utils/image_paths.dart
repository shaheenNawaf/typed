/// Resolves the local file path behind a markdown image URI.
///
/// flutter_markdown feeds every `![alt](src)` destination through
/// [Uri.tryParse]. On Windows that mangles absolute paths twice over:
/// `C:\Users\John Smith\note.png` parses with `c` as the *scheme* and the
/// space percent-encoded as `%20`, so the old `scheme == 'file'` check never
/// matched and `File(path).existsSync()` failed for files that exist.
library;

String resolveImagePath(Uri uri, {bool windows = false}) {
  if (uri.scheme == 'file') {
    try {
      return uri.toFilePath(windows: windows);
    } catch (_) {
      // Fall through to the manual decode path below.
    }
  }
  final raw = uri.toString();
  final decoded = Uri.decodeFull(raw);
  return windows ? decoded.replaceAll('/', r'\') : decoded;
}
