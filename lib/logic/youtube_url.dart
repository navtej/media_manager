/// Builds a YouTube watch URL from the video id stored at the end of a title.
String? youtubeUrlFromTitle(String title) {
  final match = RegExp(r'\[([A-Za-z0-9_-]+)\]\s*$').firstMatch(title.trim());
  final videoId = match?.group(1);
  if (videoId == null || videoId.isEmpty) {
    return null;
  }

  return Uri.https('www.youtube.com', '/watch', {'v': videoId}).toString();
}

/// Returns watch URLs for titles that contain a trailing bracketed video id.
List<String> youtubeUrlsFromTitles(Iterable<String> titles) {
  return [
    for (final title in titles)
      if (youtubeUrlFromTitle(title) case final url?) url,
  ];
}
