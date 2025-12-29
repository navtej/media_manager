# Media Manager

Media Manager is a powerful, macOS-native application built with Flutter designed to help you organize and manage your local video library effectively.

## Features

- **Native macOS Experience**: Built with `macos_ui` to feel right at home on your Mac, featuring native menus, sidebars, and alerts.
- **Smart AI Tagging**: Automatically analyzes and tags your videos using advanced AI models. The tagging process runs in a dedicated background isolate to ensure the UI remains smooth and responsive even during heavy processing.
- **Video Management**: Scan folders, view thumbnails, and organize your video collection.
- **Advanced Search**: Quickly find videos with a robust search and filtering system.
- **Metadata Extraction**: Uses FFmpeg to extract technical details and metadata from your video files.
- **Efficient Local Storage**: Powered by Drift (SQLite) for fast and reliable data persistence.

## Technologies Used

- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: [Riverpod](https://riverpod.dev)
- **Database**: [Drift](https://drift.simonbinder.eu)
- **UI Components**: [macos_ui](https://pub.dev/packages/macos_ui)
- **Video Processing**: [ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new)

## Getting Started

1.  **Prerequisites**: Ensure you have Flutter installed and set up for macOS development.
2.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```
3.  **Run the App**:
    ```bash
    flutter run -d macos
    ```

## Development

- **Generating Code**: This project uses code generation for Riverpod and Drift. Run the build runner to generate necessary files:
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```
