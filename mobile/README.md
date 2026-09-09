# Share Forge — Android

Flutter port of the desktop `share-forge` Flask app (see the
[repo root README](../README.md) for the desktop app). Unlike
[sftp-forge](https://github.com/dev-boffin-io/sftp-forge), which is a pure
client, share-forge *is* the server — so the Flutter app runs its own HTTP
server on-device via [`shelf`](https://pub.dev/packages/shelf), not just a
client SDK.

Desktop pieces that don't map to Android:

| Desktop                          | Android                                                    |
|-----------------------------------|-------------------------------------------------------------|
| Flask app (`core/server.py`)      | `shelf` server, same routes (`lib/server.dart`)             |
| Jinja2 `HTML_TEMPLATE`             | same HTML/CSS, string-built (`lib/template.dart`)            |
| System tray, multi-port `ServerCard`s | single start/stop screen + persistent notification       |
| Runs as long as the process is up | `flutter_foreground_task` keeps it alive while backgrounded |
| Any folder via a file dialog       | any folder via `file_picker`, gated behind "All files access" (`MANAGE_EXTERNAL_STORAGE`) — needed because the server reads/writes real filesystem paths, same as the desktop code |
| `io.BytesIO` in-memory ZIP         | `ZipFileEncoder` streamed to a temp file — avoids buffering a whole folder in RAM on a phone |

`MANAGE_EXTERNAL_STORAGE` (vs. Storage Access Framework) was chosen so
`lib/server.dart` can stay a near-line-for-line port of `core/server.py`
instead of rewriting every file op through a content-URI API. Fine for
direct-install APKs; would need a Play Store data-safety declaration if
this app is ever published there.

## Local dev (first run)

`android/` isn't checked in — same reasoning as sftp-forge
(`gradle-wrapper.jar` is binary and shouldn't be hand-maintained in git).
Generate it once, from inside this `mobile/` folder:

```bash
cd mobile
flutter create --platforms=android --org io.github.devboffin --project-name share_forge .
flutter pub get
flutter run
```

## CI

[`../.github/workflows/android-release.yml`](../.github/workflows/android-release.yml):
- triggers only on changes under `mobile/**` (desktop-only commits don't
  rebuild the APK)
- runs on every push to `main` touching `mobile/**` → build artifact only
- runs on `v*` tags → build + attach split-per-abi APKs to a GitHub Release
- can also be triggered manually (`workflow_dispatch`)
- generates the launcher icon from `assets/icon/icon.png` via
  `flutter_launcher_icons`, and patches the generated Gradle project for
  `compileSdk 36` and the release `INTERNET` permission — see inline
  comments in the workflow for why each patch is needed (same gotchas
  sftp-forge's CI already worked around)

Tag a commit to cut a release:

```bash
git tag v0.1.0
git push origin v0.1.0
```
