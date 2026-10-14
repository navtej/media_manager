import 'dart:convert';

import 'package:path/path.dart' as p;

import '../services/library_access_service.dart';

/// Pixel dimensions of a video stream as stored in the file.
class VideoDimensions {
  const VideoDimensions(this.width, this.height);

  final int width;
  final int height;

  int get shortSide => width < height ? width : height;
  int get longSide => width < height ? height : width;

  /// Resolution class in the familiar "1080p" sense: the frame height of the
  /// smallest 16:9 frame (in either orientation) that contains this video.
  int get qualityClass {
    final normalized = longSide * 9 / 16;
    final value = (normalized > shortSide ? normalized : shortSide).round();
    for (final standard in _standardQualityClasses) {
      if ((value - standard).abs() <= standard * 0.03) {
        return standard;
      }
    }
    return value;
  }

  String get qualityLabel => '${qualityClass}p';

  String get label => '$width×$height';

  @override
  bool operator ==(Object other) =>
      other is VideoDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => label;
}

const _standardQualityClasses = <int>[
  144,
  240,
  360,
  480,
  540,
  576,
  720,
  1080,
  1440,
  2160,
  4320,
];

/// Lower-resolution targets offered for conversion. Each preset is a 16:9
/// bounding box (flipped for portrait video); output keeps the aspect ratio.
enum VideoResolutionPreset {
  uhd2160(2160, 3840, 16000),
  qhd1440(1440, 2560, 9000),
  fhd1080(1080, 1920, 5000),
  hd720(720, 1280, 2500),
  sd480(480, 854, 1200),
  sd360(360, 640, 700);

  const VideoResolutionPreset(
    this.shortSide,
    this.longSide,
    this.videoBitrateKbps,
  );

  /// Frame height of the 16:9 box, e.g. 720.
  final int shortSide;

  /// Frame width of the 16:9 box, e.g. 1280.
  final int longSide;

  /// Target hardware-encoder bitrate before any source-based cap.
  final int videoBitrateKbps;

  String get label => '${shortSide}p';

  static VideoResolutionPreset? fromName(String? name) {
    for (final preset in values) {
      if (preset.name == name) return preset;
    }
    return null;
  }

  /// Presets that are strictly lower than [source]. Unknown dimensions offer
  /// every preset; the conversion job re-checks against a fresh probe.
  static List<VideoResolutionPreset> below(VideoDimensions? source) {
    if (source == null) return values;
    return values
        .where((preset) => preset.shortSide < source.qualityClass)
        .toList(growable: false);
  }
}

Map<String, dynamic>? decodeVideoMetadataJson(String json) {
  try {
    final decoded = jsonDecode(json);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Streams reported by `MediaService.getMetadata` (`metadata['raw']['streams']`).
List<Map<String, dynamic>> videoMetadataStreams(Map<String, dynamic> metadata) {
  final raw = metadata['raw'];
  if (raw is! Map) return const [];
  final streams = raw['streams'];
  if (streams is! List) return const [];
  return [
    for (final stream in streams)
      if (stream is Map) Map<String, dynamic>.from(stream),
  ];
}

/// The main picture stream, skipping embedded cover art.
Map<String, dynamic>? primaryVideoStream(Map<String, dynamic> metadata) {
  for (final stream in videoMetadataStreams(metadata)) {
    if (stream['codec_type'] != 'video') continue;
    final disposition = stream['disposition'];
    if (disposition is Map && _asInt(disposition['attached_pic']) == 1) {
      continue;
    }
    if ((_asInt(stream['width']) ?? 0) <= 0 ||
        (_asInt(stream['height']) ?? 0) <= 0) {
      continue;
    }
    return stream;
  }
  return null;
}

VideoDimensions? videoDimensionsFromMetadata(Map<String, dynamic> metadata) {
  final stream = primaryVideoStream(metadata);
  if (stream == null) return null;
  return VideoDimensions(_asInt(stream['width'])!, _asInt(stream['height'])!);
}

VideoDimensions? videoDimensionsFromMetadataJson(String json) {
  final metadata = decodeVideoMetadataJson(json);
  return metadata == null ? null : videoDimensionsFromMetadata(metadata);
}

String? videoCodecFromMetadata(Map<String, dynamic> metadata) {
  final codec = primaryVideoStream(metadata)?['codec_name'];
  return codec is String && codec.isNotEmpty ? codec : null;
}

/// Duration in seconds as reported by `MediaService.getMetadata`.
double? videoDurationFromMetadata(Map<String, dynamic> metadata) {
  final value = metadata['duration'];
  if (value is num && value > 0) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// One file that belongs to a catalog video.
///
/// A video that was never converted has a single implicit version built from
/// its `videos` row ([id] is null). Once converted, every file has a
/// `video_versions` row and the one whose path equals `videos.absolute_path`
/// is the primary (the file used for playback, summaries and moves).
class VideoVersionInfo {
  const VideoVersionInfo({
    required this.id,
    required this.videoId,
    required this.path,
    required this.dimensions,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.isOriginal,
    required this.isPrimary,
    this.videoCodec,
    this.createdAt,
  });

  /// `video_versions.id`, or null for the implicit version of an unconverted
  /// video.
  final int? id;
  final int videoId;
  final String path;
  final VideoDimensions? dimensions;
  final int durationSeconds;
  final int sizeBytes;
  final bool isOriginal;
  final bool isPrimary;
  final String? videoCodec;
  final DateTime? createdAt;

  String get fileName => p.basename(path);

  String get qualityLabel => dimensions?.qualityLabel ?? 'Unknown';

  String get resolutionLabel => dimensions?.label ?? 'Unknown resolution';

  String get kindLabel => isOriginal ? 'Original' : 'Converted';
}

/// Everything a conversion job needs, decided when the job starts.
class VideoConversionPlan {
  const VideoConversionPlan({
    required this.videoId,
    required this.videoTitle,
    required this.folderId,
    required this.libraryAccess,
    required this.source,
    required this.preset,
    required this.keepSource,
    required this.outputPath,
    required this.temporaryPath,
  });

  final int videoId;
  final String videoTitle;
  final int folderId;

  /// Security-scoped access for the library that holds every path below.
  final LibraryAccessRequest libraryAccess;

  /// The version being converted.
  final VideoVersionInfo source;
  final VideoResolutionPreset preset;

  /// False means the source file is removed and the new file becomes primary.
  final bool keepSource;

  /// Final location of the converted file (same directory as [source]).
  final String outputPath;

  /// Where the transcoder writes; renamed to [outputPath] when finalized.
  final String temporaryPath;
}

class VideoConversionOutcome {
  const VideoConversionOutcome({
    required this.version,
    required this.replacedSource,
    this.warnings = const <String>[],
  });

  /// The converted file as now registered in the catalog.
  final VideoVersionInfo version;

  /// True when the source file was removed and the catalog now points at the
  /// converted file.
  final bool replacedSource;

  /// Non-fatal problems, e.g. the source file could not be deleted.
  final List<String> warnings;
}

class VideoVersionDeletionResult {
  const VideoVersionDeletionResult({
    required this.deletedPaths,
    this.failures = const <String, String>{},
    this.newPrimaryPath,
  });

  final List<String> deletedPaths;

  /// Path → user-facing reason for versions that were not deleted.
  final Map<String, String> failures;

  /// Set when the primary version changed because it was deleted.
  final String? newPrimaryPath;

  String get userMessage {
    final deleted = deletedPaths.length;
    final versionText = deleted == 1 ? '1 version' : '$deleted versions';
    if (failures.isEmpty) {
      return 'Deleted $versionText.';
    }
    final firstFailure = failures.values.first;
    if (deleted == 0) {
      return 'No versions were deleted. $firstFailure';
    }
    return 'Deleted $versionText; ${failures.length} not deleted. $firstFailure';
  }
}

/// A version operation that cannot proceed. [message] is user-facing.
class VideoVersionException implements Exception {
  const VideoVersionException(this.message);

  final String message;

  @override
  String toString() => message;
}
