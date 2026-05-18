import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/app_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.moviemanager/app_lifecycle');

  tearDown(() {
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
}
