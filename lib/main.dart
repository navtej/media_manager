import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'ui/screens/home_screen.dart';

import 'services/app_lifecycle_service.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/widgets/about_dialog.dart';
import 'ui/widgets/private_library_auto_lock_lifecycle.dart';

import 'logic/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: MovieManagerApp()));
}

class MovieManagerApp extends StatefulWidget {
  const MovieManagerApp({super.key});

  @override
  State<MovieManagerApp> createState() => _MovieManagerAppState();
}

class _MovieManagerAppState extends State<MovieManagerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final appearance = ref.watch(appearanceConfigurationProvider);
        final appearanceThemeMode =
            appearance.asData?.value.themeMode ??
            AppearanceConfiguration.defaults.themeMode;
        final themeMode = switch (appearanceThemeMode) {
          AppearanceThemeMode.light => ThemeMode.light,
          AppearanceThemeMode.dark => ThemeMode.dark,
          AppearanceThemeMode.system => ThemeMode.system,
        };

        return PlatformMenuBar(
          menus: [
            PlatformMenu(
              label: 'Media Manager',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'About Media Manager',
                      onSelected: () {
                        showAppAboutDialog(_navigatorKey.currentContext!);
                      },
                    ),
                    PlatformMenuItem(
                      label: 'Preferences...',
                      shortcut: const CharacterActivator(',', meta: true),
                      onSelected: () {
                        _navigatorKey.currentState?.push(
                          CupertinoPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    PlatformMenuItem(
                      label: 'Quit Media Manager',
                      shortcut: const CharacterActivator('q', meta: true),
                      onSelected: AppLifecycleService.quit,
                    ),
                  ],
                ),
              ],
            ),
          ],
          child: MacosApp(
            navigatorKey: _navigatorKey,
            title: 'Media Manager',
            theme: MacosThemeData.light(),
            darkTheme: MacosThemeData.dark(),
            themeMode: themeMode,
            debugShowCheckedModeBanner: false,
            home: const PrivateLibraryAutoLockLifecycle(child: HomeScreen()),
          ),
        );
      },
    );
  }
}
