# EventTrack

## Run the apps

```sh
flutter run --flavor student -t lib/main_student.dart
flutter run --flavor admin -t lib/main_admin.dart
```

To display administrator credentials on a local demonstration build, copy
`scripts/admin-demo.example.json` to `.firebase/admin-demo.json` and fill in the
local account details. The `.firebase` directory is ignored by Git.

```sh
flutter run --flavor admin -t lib/main_admin.dart --dart-define-from-file=.firebase/admin-demo.json
```

VS Code also provides an **Admin App (local demo)** launch configuration.
Normal builds omit the credentials panel. Do not commit real passwords or
database exports.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
