/// [path] in the form Flutter compares widget creation locations against: the
/// path of its `file:` URI. A POSIX path is already in that form; `D:\app`
/// becomes `/D:/app`. Sent as it is, a Windows path matches no location, no
/// widget counts as the app's own, and a whole screen under one gesture
/// handler is reported as a single tappable element.
String creationLocationRoot(String path) {
  final windows = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  final uriPath = Uri.file(path, windows: windows).path;
  return uriPath.length > 1 && uriPath.endsWith('/')
      ? uriPath.substring(0, uriPath.length - 1)
      : uriPath;
}

/// The path of a `file:` URI as the file system takes it: a Windows drive
/// path comes out of a URI as `/D:/app`, which `Directory` rejects.
String fileSystemPath(String uriPath) =>
    RegExp(r'^/[A-Za-z]:(/|$)').hasMatch(uriPath)
    ? Uri.decodeComponent(uriPath.substring(1))
    : Uri.decodeComponent(uriPath);
