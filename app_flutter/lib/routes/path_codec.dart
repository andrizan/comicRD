String encodeRoutePath(String path) => Uri.encodeComponent(path);

String decodeRoutePath(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
