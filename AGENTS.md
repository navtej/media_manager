@/Users/navtej/.codex/RTK.md

# Linear

- Manage MovieManager work under the `Personal` team (`PER`) in Linear.
- Use the `MovieManager Architecture` project for architecture-related work in this repository.
- Linear team ID: `4bfd6f14-0f73-40d4-a38c-70fec99d87a1`.
- Linear project ID: `768bee20-9187-4b6b-9a26-45f3b0b41afc`.

## Launching Dart and Flutter Applications

- Always pass the `--print-dtd` flag to `dart` or `flutter` when spawning an
  application.
- For `dart` applications, always pass the `--observe` flag to enable the app to
  be connected to.
- Both `--print-dtd` and `--observe` must come before the script name or path
  when spawning `dart` applications: `dart --observe --print-dtd bin/main.dart`.

## Dart and Flutter MCP Server

- A Dart and Flutter MCP server is available. Use these tools at appropriate
  times when working with Dart and Flutter applications.

| Tool Name | Title | Description | Categories | Enabled |
| --- | --- | --- | --- | --- |
| `analyze_files` | Analyze projects | Analyzes specific paths, or the entire project, for errors. | analysis | Yes |
| `create_project` | Create project | Creates a new Dart or Flutter project. | cli | No |
| `dart_fix` | Dart fix | Runs `dart fix --apply` for the given project roots. | cli | No |
| `dart_format` | Dart format | Runs `dart format .` for the given project roots. | cli | No |
| `dtd` | Dart Tooling Daemon | Manage live app connections to Dart and Flutter apps using the Dart Tooling Daemon (DTD). Start by using the `listDtdUris` command to find available DTD URIs, followed by the `connect` command with the desired URI to connect to. Apps from a given DTD instance are automatically connected to, and you can use the `listConnectedApps` command to see the list of connected apps. If you see DTD instances with a working dir that looks like a home directory, these are likely connected to an IDE and you should connect to those to find IDE launched apps. | dart_tooling_daemon | Yes |
| `flutter_driver_command` | Flutter Driver | Run a flutter driver command | flutter_driver | Yes |
| `get_active_location` | Get Active Editor Location | Retrieves the current active location (e.g., cursor position) in the connected editor. Requires an active DTD connection. | dart_tooling_daemon | No |
| `get_app_logs` |  | Returns the collected logs for a given flutter run process id. Can only retrieve logs started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `get_runtime_errors` | Get runtime errors | Retrieves the most recent runtime errors that have occurred in the active Dart or Flutter application. Requires an active DTD connection. | dart_tooling_daemon | Yes |
| `hot_reload` | Hot reload | Performs a hot reload of the active Flutter application. This will apply the latest code changes to the running application, while maintaining application state. Reload will not update const definitions of global values. Requires an active DTD connection. | flutter | Yes |
| `hot_restart` | Hot restart | Performs a hot restart of the active Flutter application. This applies the latest code changes to the running application, including changes to global const values, while resetting application state. Requires an active DTD connection. Doesn't work for Non-Flutter Dart CLI programs. | flutter | Yes |
| `launch_app` |  | Launches a Flutter application and returns its DTD URI. | flutter, flutter_app_lifecycle | No |
| `list_devices` |  | Lists available Flutter devices. | flutter, flutter_app_lifecycle, cli | No |
| `list_running_apps` |  | Returns the list of running app process IDs and associated DTD URIs for apps started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `lsp` | Language Server Protocol | Interacts with the Dart Language Server Protocol (LSP) to provide code intelligence features like hover, signature help, and symbol resolution.<br>Commands:<br>- hover: Get hover information (docs, types) at a position. Requires: uri, line, column.<br>- signatureHelp: Get signature help at a position. Requires: uri, line, column.<br>- resolveWorkspaceSymbol: Fuzzy search for symbols by name. Requires: query. | analysis | Yes |
| `pub` | pub | Runs a pub command for the given project roots, like `dart pub get` or `flutter pub add`. | cli, package_deps | Yes |
| `pub_dev_search` | pub.dev search | Searches pub.dev for packages relevant to a given search query. The response will describe each result with its download count, package description, topics, license, and publisher. | package_deps | Yes |
| `read_package_uris` |  | Reads "package" and "package-root" scheme URIs which represent paths under Dart package dependencies. "package" URIs are always relative to the "lib" directory and "package-root" URIs are relative to the true root directory of the package. For example, the URI "package:test/test.dart" represents the path "lib/test.dart" under the "test" package. "package-root:test/example/test.dart" represents the path "example/test.dart". This API supports both reading files and listing directories. | package_deps | Yes |
| `rip_grep_packages` |  | Uses ripgrep to find patterns in package dependencies. Note that ripgrep must be installed already. | package_deps | Yes |
| `roots` |  | Manage project roots. | None | Yes |
| `run_tests` | Run tests | Run Dart or Flutter tests with an agent centric UX. ALWAYS use instead of `dart test` or `flutter test` shell commands. | cli | No |
| `stop_app` |  | Kills a running Flutter process started by the launch_app tool. | flutter, flutter_app_lifecycle | No |
| `vm_service` | VM Service | Manage and interact with VM service connections. This tool allows you to connect to an app using its VM service URI, disconnect from it, or invoke VM service methods directly. Connecting allows features like hot reload to work on apps not launched via DTD. | dart_tooling_daemon | Yes |
| `widget_inspector` | Widget Inspector | Interact with the Flutter widget inspector in the active Flutter application. Requires an active DTD connection. | flutter | Yes |
