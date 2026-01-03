import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showAppAboutDialog(BuildContext context) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  if (!context.mounted) return;

  showMacosAlertDialog(
    context: context,
    builder: (context) => MacosAlertDialog(
      appIcon: const MacosIcon(CupertinoIcons.film, size: 56),
      title: const Text('Media Manager'),
      message: Column(
        children: [
          Text('Version $version', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
            'Github:',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () async {
              final url = Uri.parse('https://github.com/navtej/media_manager');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
            child: const Text(
              'https://github.com/navtej/media_manager',
              style: TextStyle(
                color: MacosColors.appleBlue,
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '© 2026 Navtej Singh',
            style: TextStyle(fontSize: 10),
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        child: const Text('OK'),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
  );
}
