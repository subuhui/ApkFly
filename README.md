# Apk Fly

Apk Fly is a Flutter desktop tool for publishing Android APKs to multiple app stores from one workspace.

It is designed for Android engineers, release managers, and product or operations teammates who need a faster repeatable release flow.

## Features

- Manage per-app publishing profiles in YAML.
- Upload APKs to Huawei, Xiaomi, OPPO, VIVO, and HONOR.
- Refresh store review status from the home page.
- Match multi-channel APKs by filename marker.
- Track upload progress, retry failed submissions, and write local logs.
- Support macOS and Windows desktop packaging.

## Local Storage

Apk Fly stores runtime data in:

- `~/.apk_fly`
- `~/.apk_fly/debug` in Flutter debug mode

Profile files are saved under:

- `~/.apk_fly/apps/<applicationId>.yaml`

## Development

Flutter SDK used in this project:

- `/Users/xxz/developer/flutter`

Common commands:

```bash
/Users/xxz/developer/flutter/bin/flutter pub get
/Users/xxz/developer/flutter/bin/flutter analyze
/Users/xxz/developer/flutter/bin/flutter test
/Users/xxz/developer/flutter/bin/flutter build macos --debug
```

## Notes

- macOS file selection requires the user-selected file entitlement already configured in the project.
- Some app stores apply API-side rate limits. Apk Fly adds client-side refresh throttling, but store-side limits may still apply.
- Store credentials stay on the local machine and are written into local profile files only.

## License

This project is licensed under the Apache License 2.0.

See [LICENSE](/Users/xxz/AndroidStudioProjects/apk_fly/LICENSE).
