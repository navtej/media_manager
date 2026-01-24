import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_provider.g.dart';

@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  FutureOr<Map<String, dynamic>> build() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'scanInterval': prefs.getInt('scanInterval') ?? 5,
      'batchSize': prefs.getInt('batchSize') ?? 4,
      'themeMode': prefs.getString('themeMode') ?? 'system',
      'paginationSize': prefs.getInt('paginationSize') ?? 50,
      'showOfflineMedia': prefs.getBool('showOfflineMedia') ?? true,
    };
  }

  Future<void> updateSettings(int scanInterval, int batchSize, int paginationSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('scanInterval', scanInterval);
    await prefs.setInt('batchSize', batchSize);
    await prefs.setInt('paginationSize', paginationSize);
    
    state = AsyncData({
      ...state.value ?? {},
      'scanInterval': scanInterval,
      'batchSize': batchSize,
      'paginationSize': paginationSize,
    });
  }

  Future<void> updateShowOfflineMedia(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showOfflineMedia', value);
    
    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'showOfflineMedia': value,
    });
  }

  Future<void> updateTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode);
    
    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'themeMode': mode,
    });
  }
}
