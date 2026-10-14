import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/video_conversion_controller.dart';
import 'package:movie_manager/logic/video_version_models.dart';
import 'package:movie_manager/services/video_version_service.dart';
import 'package:movie_manager/ui/widgets/macos_preference_checkbox.dart';
import 'package:movie_manager/ui/widgets/video_conversion_dialogs.dart';
import 'package:movie_manager/ui/widgets/video_info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final now = DateTime(2026, 10, 14);
  final video = Video(
    id: 1,
    folderId: 1,
    absolutePath: '/Volumes/Media/clip.mp4',
    title: 'clip',
    duration: 3725,
    size: 2 * 1024 * 1024 * 1024,
    metadataJson: '{}',
    isOffline: false,
    isFavorite: false,
    addedAt: now,
    fileCreatedAt: now,
    aiProcessed: false,
  );
  const original = VideoVersionInfo(
    id: 10,
    videoId: 1,
    path: '/Volumes/Media/clip.mp4',
    dimensions: VideoDimensions(1920, 1080),
    durationSeconds: 3725,
    sizeBytes: 2 * 1024 * 1024 * 1024,
    isOriginal: true,
    isPrimary: true,
    videoCodec: 'hevc',
  );
  const converted = VideoVersionInfo(
    id: 11,
    videoId: 1,
    path: '/Volumes/Media/clip [720p].mp4',
    dimensions: VideoDimensions(1280, 720),
    durationSeconds: 3725,
    sizeBytes: 700 * 1024 * 1024,
    isOriginal: false,
    isPrimary: false,
    videoCodec: 'h264',
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Widget dialog,
    required List overrides,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides],
        child: MacosApp(
          home: MacosWindow(
            child: Builder(
              builder: (context) => Center(
                child: PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () => showMacosAlertDialog<void>(
                    context: context,
                    builder: (_) => dialog,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('info dialog lists versions with resolution, duration and size', (
    tester,
  ) async {
    final service = _RecordingVersionService();
    await pumpDialog(
      tester,
      dialog: VideoInfoDialog(video: video),
      overrides: [
        videoVersionsProvider.overrideWith(
          (ref, _) => Stream.value(const [original, converted]),
        ),
        videoVersionServiceProvider.overrideWithValue(service),
      ],
    );

    expect(find.text('Video Information'), findsOneWidget);
    expect(find.text('Versions (2)'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('1920×1080 · HEVC · 1:02:05 · 2.0 GB'), findsOneWidget);
    expect(find.text('1280×720 · H.264 · 1:02:05 · 700.0 MB'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Converted'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('clip [720p].mp4'), findsOneWidget);
    expect(find.text('Use for Playback'), findsOneWidget);

    // Nothing selected: delete is disabled.
    final deleteButton = find.byKey(
      const ValueKey('video-info-delete-versions-button'),
    );
    expect(tester.widget<PushButton>(deleteButton).onPressed, isNull);

    await tester.tap(find.text('Use for Playback'));
    await tester.pumpAndSettle();
    expect(service.primaryPaths, [converted.path]);

    // Selecting every version keeps delete disabled.
    final checkboxes = find.byType(MacosPreferenceCheckbox);
    expect(checkboxes, findsNWidgets(2));
    await tester.tap(checkboxes.first);
    await tester.tap(checkboxes.last);
    await tester.pump();
    expect(tester.widget<PushButton>(deleteButton).onPressed, isNull);
    expect(find.textContaining('Keep at least one version'), findsOneWidget);

    await tester.tap(checkboxes.first);
    await tester.pump();
    expect(tester.widget<PushButton>(deleteButton).onPressed, isNotNull);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete Version?'), findsOneWidget);
    expect(
      find.textContaining('permanently deletes clip [720p].mp4'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(service.deletedPaths, [
      [converted.path],
    ]);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Video Information'), findsNothing);
  });

  testWidgets('info dialog shows an active conversion and pauses edits', (
    tester,
  ) async {
    const job = VideoConversionJob(
      id: 7,
      videoId: 1,
      title: 'clip',
      preset: VideoResolutionPreset.sd480,
      keepSource: false,
      status: VideoConversionStatus.converting,
      progress: 0.42,
    );
    final controller = _RecordingConversionController(
      const VideoConversionState(jobs: [job]),
    );
    await pumpDialog(
      tester,
      dialog: VideoInfoDialog(video: video),
      overrides: [
        videoVersionsProvider.overrideWith(
          (ref, _) => Stream.value(const [original, converted]),
        ),
        videoVersionServiceProvider.overrideWithValue(
          _RecordingVersionService(),
        ),
        videoConversionControllerProvider.overrideWith(() => controller),
      ],
    );

    expect(
      find.text('480p · Replace original · Converting 42%'),
      findsOneWidget,
    );
    expect(find.byType(ProgressBar), findsOneWidget);
    expect(find.textContaining('paused while this video'), findsOneWidget);
    expect(
      tester
          .widget<PushButton>(
            find.byKey(const ValueKey('video-info-convert-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PushButton>(
            find.ancestor(
              of: find.text('Use for Playback'),
              matching: find.byType(PushButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(controller.cancelledJobIds, [7]);
  });

  testWidgets('conversion dialog offers lower resolutions and queues the job', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Media'),
    );
    final videoId = await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: '/Volumes/Media/clip.mp4',
        title: 'clip',
        duration: const drift.Value(600),
        size: const drift.Value(600 * 1000 * 1000),
        metadataJson: drift.Value(
          jsonEncode({
            'raw': {
              'streams': [
                {
                  'index': 0,
                  'codec_type': 'video',
                  'codec_name': 'h264',
                  'width': 1920,
                  'height': 1080,
                },
              ],
            },
          }),
        ),
      ),
    );
    final controller = _RecordingConversionController(
      const VideoConversionState(),
    );

    await pumpDialog(
      tester,
      dialog: VideoConversionDialog(videoIds: [videoId]),
      overrides: [
        databaseProvider.overrideWithValue(db),
        videoConversionControllerProvider.overrideWith(() => controller),
      ],
    );

    expect(find.text('Convert to Lower Resolution'), findsOneWidget);
    expect(
      find.text('Source: Original · 1920×1080 (1080p) · 10:00 · 572.2 MB'),
      findsOneWidget,
    );
    // Remembered default (720p) is offered for a 1080p source.
    expect(find.text('720p'), findsOneWidget);
    expect(
      find.textContaining('Fits within 1280×720 (720×1280 for portrait'),
      findsOneWidget,
    );
    expect(find.text('Estimated size: about 190.3 MB'), findsOneWidget);
    expect(find.text('Keep the original file'), findsOneWidget);
    expect(find.textContaining('saved next to the original'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('video-conversion-keep-original')),
    );
    await tester.pump();
    expect(find.textContaining('the original is deleted'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('video-conversion-convert-button')),
    );
    await tester.pumpAndSettle();

    final call = controller.enqueued.single;
    expect(call.videoIds, [videoId]);
    expect(call.preset, VideoResolutionPreset.hd720);
    expect(call.keep, isFalse);
    expect(find.text('Convert to Lower Resolution'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('queue dialog lists jobs, cancels and clears finished ones', (
    tester,
  ) async {
    final controller = _RecordingConversionController(
      const VideoConversionState(
        jobs: [
          VideoConversionJob(
            id: 1,
            videoId: 1,
            title: 'done movie',
            preset: VideoResolutionPreset.hd720,
            keepSource: true,
            status: VideoConversionStatus.completed,
            message: 'Saved done movie [720p].mp4 (1280×720).',
          ),
          VideoConversionJob(
            id: 2,
            videoId: 2,
            title: 'broken movie',
            preset: VideoResolutionPreset.hd720,
            keepSource: true,
            status: VideoConversionStatus.failed,
            message: 'FFmpeg couldn’t convert “broken movie”: bad data',
          ),
          VideoConversionJob(
            id: 3,
            videoId: 3,
            title: 'waiting movie',
            preset: VideoResolutionPreset.sd480,
            keepSource: false,
          ),
          VideoConversionJob(
            id: 4,
            videoId: 4,
            title: 'secret movie',
            preset: VideoResolutionPreset.hd720,
            keepSource: true,
            isPrivate: true,
            status: VideoConversionStatus.completed,
            message: 'Saved secret movie [720p].mp4 (1280×720).',
          ),
        ],
      ),
    );
    await pumpDialog(
      tester,
      dialog: const VideoConversionQueueDialog(),
      overrides: [
        videoConversionControllerProvider.overrideWith(() => controller),
      ],
    );

    expect(find.text('Video Conversions'), findsOneWidget);
    expect(find.text('done movie'), findsOneWidget);
    expect(find.text('720p · Keep original · Done'), findsNWidgets(2));
    expect(
      find.text('FFmpeg couldn’t convert “broken movie”: bad data'),
      findsOneWidget,
    );
    expect(find.text('480p · Replace original · Queued'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Private libraries are locked by default: no title or file name.
    expect(find.text('Private video'), findsOneWidget);
    expect(find.textContaining('secret movie'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(controller.cancelledJobIds, [3]);

    await tester.tap(find.text('Clear Finished'));
    await tester.pump();
    expect(controller.clearedFinished, isTrue);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Video Conversions'), findsNothing);
  });
}

class _RecordingConversionController extends VideoConversionController {
  _RecordingConversionController(this._initial);

  final VideoConversionState _initial;
  final enqueued =
      <({List<int> videoIds, VideoResolutionPreset preset, bool keep})>[];
  final cancelledJobIds = <int>[];
  bool clearedFinished = false;

  @override
  VideoConversionState build() => _initial;

  @override
  Future<VideoConversionEnqueueResult> enqueue({
    required List<int> videoIds,
    required VideoResolutionPreset preset,
    required bool keepSource,
  }) async {
    enqueued.add((videoIds: videoIds, preset: preset, keep: keepSource));
    return VideoConversionEnqueueResult(queued: videoIds.length);
  }

  @override
  void cancel(int jobId) => cancelledJobIds.add(jobId);

  @override
  void clearFinished() => clearedFinished = true;
}

class _RecordingVersionService implements VideoVersionService {
  final primaryPaths = <String>[];
  final deletedPaths = <List<String>>[];

  @override
  Future<void> setPrimaryVersion({
    required int videoId,
    required String path,
  }) async {
    primaryPaths.add(path);
  }

  @override
  Future<VideoVersionDeletionResult> deleteVersions({
    required int videoId,
    required Iterable<String> paths,
  }) async {
    final list = paths.toList();
    deletedPaths.add(list);
    return VideoVersionDeletionResult(deletedPaths: list);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
