import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/library_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryAccessService', () {
    test('keeps nested access alive until the outer owner finishes', () async {
      final adapter = _RecordingLibraryAccessAdapter();
      final service = LibraryAccessService(adapter: adapter);

      await service.withAccess(
        library: _libraryRequest(),
        action: () async {
          await service.withAccess(
            library: _libraryRequest(),
            action: () async {
              expect(adapter.events, ['start:/Library:bookmark']);
            },
          );
          expect(adapter.events, ['start:/Library:bookmark']);
        },
      );

      expect(adapter.events, ['start:/Library:bookmark', 'stop:/Library']);
    });

    test('overlapping owners share one native access lifetime', () async {
      final adapter = _RecordingLibraryAccessAdapter();
      final service = LibraryAccessService(adapter: adapter);
      final firstCanFinish = Completer<void>();
      final secondCanFinish = Completer<void>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();

      final first = service.withAccess(
        library: _libraryRequest(),
        action: () async {
          firstStarted.complete();
          await firstCanFinish.future;
        },
      );
      await firstStarted.future;
      final second = service.withAccess(
        library: _libraryRequest(),
        action: () async {
          secondStarted.complete();
          await secondCanFinish.future;
        },
      );
      await secondStarted.future;

      expect(adapter.events, ['start:/Library:bookmark']);
      firstCanFinish.complete();
      await first;
      expect(adapter.events, ['start:/Library:bookmark']);

      secondCanFinish.complete();
      await second;
      expect(adapter.events, ['start:/Library:bookmark', 'stop:/Library']);
    });

    test(
      'failed acquisition returns one repair outcome without work',
      () async {
        final adapter = _RecordingLibraryAccessAdapter(canStart: false);
        final service = LibraryAccessService(adapter: adapter);
        var actionCount = 0;

        for (final bookmark in <String?>[null, '', 'invalid-or-stale']) {
          await expectLater(
            service.withAccess(
              library: _libraryRequest(bookmark),
              action: () async => actionCount += 1,
            ),
            throwsA(
              isA<LibraryAccessNeedsRepairException>().having(
                (error) => error.message,
                'message',
                libraryAccessRepairMessage,
              ),
            ),
          );
        }

        expect(actionCount, 0);
        expect(adapter.events, ['start:/Library:invalid-or-stale']);
      },
    );

    test('releases access after operation errors and cancellation', () async {
      final adapter = _RecordingLibraryAccessAdapter();
      final service = LibraryAccessService(adapter: adapter);

      await expectLater(
        service.withAccess<void>(
          library: _libraryRequest(),
          action: () async => throw StateError('operation failed'),
        ),
        throwsStateError,
      );
      await expectLater(
        service.withAccess<void>(
          library: _libraryRequest(),
          action: () async => throw const _OperationCanceled(),
        ),
        throwsA(isA<_OperationCanceled>()),
      );

      expect(adapter.events, [
        'start:/Library:bookmark',
        'stop:/Library',
        'start:/Library:bookmark',
        'stop:/Library',
      ]);
    });

    test(
      'releases earlier libraries when multi-library access fails',
      () async {
        final adapter = _RecordingLibraryAccessAdapter(
          deniedPaths: {'/Destination'},
        );
        final service = LibraryAccessService(adapter: adapter);
        var actionRan = false;

        await expectLater(
          service.withAccessToAll(
            libraries: const [
              LibraryAccessRequest(path: '/Source', bookmark: 'source'),
              LibraryAccessRequest(
                path: '/Destination',
                bookmark: 'destination',
              ),
            ],
            action: () async => actionRan = true,
          ),
          throwsA(isA<LibraryAccessNeedsRepairException>()),
        );

        expect(actionRan, isFalse);
        expect(adapter.events, [
          'start:/Source:source',
          'start:/Destination:destination',
          'stop:/Source',
        ]);
      },
    );
  });

  group('MethodChannelLibraryAccessAdapter', () {
    const channel = MethodChannel('library-access-adapter-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('creates bookmarks through the native adapter', () async {
      MethodCall? receivedCall;
      messenger.setMockMethodCallHandler(channel, (call) async {
        receivedCall = call;
        return 'created-bookmark';
      });
      final adapter = MethodChannelLibraryAccessAdapter(
        channel: channel,
        isMacOS: true,
      );

      final bookmark = await adapter.createBookmark('/Library');

      expect(bookmark, 'created-bookmark');
      expect(receivedCall?.method, 'createFolderBookmark');
      expect(receivedCall?.arguments, {'path': '/Library'});
    });

    test('maps stale bookmarks to failed acquisition', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startAccessingFolder') {
          return false;
        }
        return null;
      });
      final adapter = MethodChannelLibraryAccessAdapter(
        channel: channel,
        isMacOS: true,
      );

      expect(
        await adapter.startAccessing(
          path: '/Library',
          bookmark: 'stale-bookmark',
        ),
        isFalse,
      );
    });

    test('stops native access only after the final service owner', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'startAccessingFolder') {
          return true;
        }
        return null;
      });
      final adapter = MethodChannelLibraryAccessAdapter(
        channel: channel,
        isMacOS: true,
      );
      final service = LibraryAccessService(adapter: adapter);

      await service.withAccess(
        library: _libraryRequest(),
        action: () =>
            service.withAccess(library: _libraryRequest(), action: () async {}),
      );

      expect(calls, ['startAccessingFolder', 'stopAccessingFolder']);
    });
  });
}

LibraryAccessRequest _libraryRequest([String? bookmark = 'bookmark']) {
  return LibraryAccessRequest(path: '/Library', bookmark: bookmark);
}

class _RecordingLibraryAccessAdapter implements LibraryAccessAdapter {
  _RecordingLibraryAccessAdapter({
    this.canStart = true,
    this.deniedPaths = const {},
  });

  final bool canStart;
  final Set<String> deniedPaths;
  final List<String> events = [];

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    events.add('start:$path:$bookmark');
    return canStart && !deniedPaths.contains(path);
  }

  @override
  Future<void> stopAccessing(String path) async {
    events.add('stop:$path');
  }
}

class _OperationCanceled implements Exception {
  const _OperationCanceled();
}
