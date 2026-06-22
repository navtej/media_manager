import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.example.moviemanager/private_library_auth',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('authenticate returns native owner-auth result', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });

    final authenticated = await PrivateLibraryAuthService().authenticate();

    expect(authenticated, isTrue);
    expect(calls.single.method, 'authenticatePrivateLibrary');
  });

  test('authenticate returns false when native auth is cancelled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(await PrivateLibraryAuthService().authenticate(), isFalse);
  });

  test('authenticate returns false when native auth throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'AUTH_FAILED', message: 'Cancelled');
        });

    expect(await PrivateLibraryAuthService().authenticate(), isFalse);
  });
}
