import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_provider.g.dart';

@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  FutureOr<Map<String, int>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('scan_interval') ?? 5;
    final batchSize = prefs.getInt('batch_size') ?? 4;
    return {
      'scanInterval': interval,
      'batchSize': batchSize,
    };
  }

  Future<void> updateSettings(int interval, int batchSize) async {
    if (interval < 1) interval = 1;
    if (batchSize < 1) batchSize = 1;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('scan_interval', interval);
    await prefs.setInt('batch_size', batchSize);
    
    state = AsyncValue.data({
      'scanInterval': interval,
      'batchSize': batchSize,
    });
  }
}
