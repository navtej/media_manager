import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/whisper_model_catalog.dart';

void main() {
  group('builtInWhisperModelCatalog', () {
    test(
      'contains multilingual and english-only variants with published sizes',
      () {
        final ids = builtInWhisperModelCatalog
            .map((entry) => entry.id)
            .toList();

        expect(
          ids,
          containsAll(<String>[
            'tiny.en',
            'tiny',
            'base.en',
            'base',
            'small.en',
            'small',
            'medium.en',
            'medium',
            'large-v1',
            'large-v2',
            'large-v3',
            'large-v3-turbo',
          ]),
        );

        expect(
          builtInWhisperModelCatalog
              .firstWhere((entry) => entry.id == 'base.en')
              .diskSizeLabel,
          '142 MiB',
        );
        expect(
          builtInWhisperModelCatalog
              .firstWhere((entry) => entry.id == 'large-v3')
              .diskSizeLabel,
          '2.9 GiB',
        );
      },
    );

    test('maps family sizes consistently across related variants', () {
      final medium = builtInWhisperModelCatalog.firstWhere(
        (entry) => entry.id == 'medium',
      );
      final mediumEn = builtInWhisperModelCatalog.firstWhere(
        (entry) => entry.id == 'medium.en',
      );

      expect(medium.diskSizeBytes, mediumEn.diskSizeBytes);
      expect(medium.family, 'medium');
      expect(mediumEn.family, 'medium');
    });
  });

  group('parseWhisperCppReadmeMetadata', () {
    test(
      'parses model variants and family disk sizes from README snippets',
      () {
        const readme = '''
You can download and run the other models as follows:
    make -j tiny.en
    make -j tiny
    make -j base.en
    make -j base
    make -j small.en
    make -j small
    make -j medium.en
    make -j medium
    make -j large-v1
    make -j large-v2
    make -j large-v3
    make -j large-v3-turbo

## Memory usage
Model Disk Mem
tiny 75 MiB ~273 MB
base 142 MiB ~388 MB
small 466 MiB ~852 MB
medium 1.5 GiB ~2.1 GB
large 2.9 GiB ~3.9 GB
''';

        final metadata = parseWhisperCppReadmeMetadata(readme);

        expect(
          metadata.entries
              .firstWhere((entry) => entry.id == 'tiny.en')
              .diskSizeLabel,
          '75 MiB',
        );
        expect(
          metadata.entries
              .firstWhere((entry) => entry.id == 'large-v3-turbo')
              .diskSizeLabel,
          '2.9 GiB',
        );
      },
    );

    test('parses current README markdown table format', () {
      const readme = '''
You can download and run the other models as follows:
```bash
make -j tiny.en
make -j tiny
make -j base.en
make -j base
make -j medium.en
make -j medium
make -j large-v3
```

## Memory usage
| Model | Disk | Mem |
| ------ | ---- | --- |
| tiny | 75 MiB | ~273 MB |
| base | 142 MiB | ~388 MB |
| medium | 1.5 GiB | ~2.1 GB |
| large | 2.9 GiB | ~3.9 GB |
''';

      final metadata = parseWhisperCppReadmeMetadata(readme);

      expect(
        metadata.entries.map((entry) => entry.id),
        containsAll(<String>[
          'tiny.en',
          'tiny',
          'base.en',
          'base',
          'medium.en',
          'medium',
          'large-v3',
        ]),
      );
      expect(
        metadata.entries
            .firstWhere((entry) => entry.id == 'medium.en')
            .diskSizeLabel,
        '1.5 GiB',
      );
    });
  });

  group('ModelDownloadState', () {
    test('computes determinate progress and eta when total size is known', () {
      const state = ModelDownloadState(
        phase: ModelDownloadPhase.downloading,
        modelId: 'base.en',
        receivedBytes: 1572864,
        totalBytes: 3145728,
        bytesPerSecond: 524288,
        eta: Duration(seconds: 5),
        error: null,
      );

      expect(state.progressFraction, 0.5);
      expect(state.hasDeterminateProgress, isTrue);
      expect(state.eta, const Duration(seconds: 5));
      expect(state.percentage, 50);
      expect(state.percentLabel, '50%');
      expect(state.formattedReceivedBytes, '1.50 MiB');
      expect(state.formattedTotalBytes, '3.00 MiB');
      expect(state.formattedBytesPerSecond, '512.00 KiB/s');
      expect(state.formattedEta, '00:05');
    });

    test('falls back to indeterminate progress when total size is unknown', () {
      const state = ModelDownloadState(
        phase: ModelDownloadPhase.downloading,
        modelId: 'base.en',
        receivedBytes: 1536,
        totalBytes: null,
        bytesPerSecond: 128,
        eta: null,
        error: null,
      );

      expect(state.progressFraction, isNull);
      expect(state.hasDeterminateProgress, isFalse);
      expect(state.eta, isNull);
      expect(state.percentage, isNull);
      expect(state.formattedReceivedBytes, '1.50 KiB');
      expect(state.formattedTotalBytes, 'Unknown');
      expect(state.formattedBytesPerSecond, '128.00 B/s');
      expect(state.formattedEta, 'Unknown');
    });
  });

  group('managed model path checks', () {
    test('allows delete only for files inside the managed model directory', () {
      expect(
        isManagedModelPath(
          modelPath:
              '/Users/test/Library/Application Support/Media Manager/models/ggml-base.en.bin',
          managedDirectoryPath:
              '/Users/test/Library/Application Support/Media Manager/models',
        ),
        isTrue,
      );

      expect(
        isManagedModelPath(
          modelPath: '/Applications/OtherApp/models/ggml-base.en.bin',
          managedDirectoryPath:
              '/Users/test/Library/Application Support/Media Manager/models',
        ),
        isFalse,
      );
    });
  });
}
