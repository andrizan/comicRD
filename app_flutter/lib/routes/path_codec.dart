String encodeRoutePath(String path) => Uri.encodeComponent(path);

String decodeRoutePath(String value) => Uri.decodeComponent(value);
