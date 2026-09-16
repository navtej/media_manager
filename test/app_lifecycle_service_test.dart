import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/app_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.moviemanager/app_lifecycle');

  tearDown(() {
    AppLifecycleService.unregisterTerminationHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('quit requests native app termination', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await AppLifecycleService.quit();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'terminateApplication');
  });

  test(
    'native termination requests await the registered cleanup handler',
    () async {
      var cleanupCalls = 0;
      AppLifecycleService.registerTerminationHandler(() async {
        cleanupCalls += 1;
      });

      final response = await TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('prepareForTermination'),
            ),
            null,
          );

      expect(cleanupCalls, 1);
      expect(response, isNotNull);
      expect(const StandardMethodCodec().decodeEnvelope(response!), isNull);
    },
  );
}
