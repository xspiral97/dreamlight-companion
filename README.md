# Dreamlight Companion

Unofficial Flutter companion for Disney Dreamlight Valley on Windows, Android and macOS. English interface; SQLite data stays on your device. No account or game-save modification.

## Version 0.2.0

- Crop planner includes 50 bundled crop/material pictures (regular plantable ingredients, seasonal Spring V-EGG-etable and Cotton), plus the actual Wishing Well icon. New seed-grown ingredients and image URLs are discovered by wiki refresh.
- Floating islands use 65×65 planting cells, with an optional 130×130 placement subgrid. A well occupies 6×6 planting cells (12×12 placement units). Its initial position is an editable planning marker.
- Other biome names are available as map labels with user-measured dimensions. **Exact biome boundaries and blocked terrain masks have not been verified or bundled.** Configure dimensions and mark blocked cells to match your map. Do not treat the legacy 32×32 grid as a measured game map.
- Blocked cells and well footprints reject crop placement, resizing and dragging. Existing layouts keep their original dimensions and coordinates. Backup validation supports variable map sizes.
- Refresh uses rendered collection pages instead of the allpages generator that was returning HTTP 403. All 16 current collection sources were verified live (8,433 collection memberships; shared entries use the same page ID). Successful sources are saved independently; a failed source preserves old data and appears in the status. Automatic failed retries are throttled to one hour.
- A bundled catalog starts offline. Full page text downloads when opened; detail packs can be cached from Settings. Pictures of the 50 bundled crops and well work offline; other images cache on demand. All text and image attribution is in ATTRIBUTION.md.

## Updates

Repository: https://github.com/xspiral97/dreamlight-companion

Settings → Check for updates reads the latest stable GitHub Release, compares semantic versions, and verifies the asset's GitHub-provided SHA-256 digest. Drafts, prereleases and downgrades are ignored.

Windows downloads the portable ZIP, rejects unsafe archive paths, validates required runtime files, backs up personal data, then restarts using a helper that waits for the old process to exit and backs up overwritten files. On a copy failure existing files are restored. A read-only install directory is reported before the application exits. Logs and backups are under application support / updates. Personal SQLite data is outside the installation directory.

Android downloads and verifies the APK inside the application, then opens the Android system update confirmation. Permission to install updates from this app must be enabled once. The existing signing key is preserved locally and in a GitHub Actions secret so future packages can replace the installed version without clearing data. These are personal testing builds, not Play Store releases. Android runtime updater testing on a physical device remains outstanding.

macOS currently opens the release page; automatic app replacement is not implemented there. macOS compilation requires a Mac. This Windows host cannot validate a native macOS build.

Version 0.1.0 did not include an updater: install or extract 0.2.0 once to enable future in-app updates.

## Run and build

Install Flutter stable and run `flutter pub get`, then `flutter run -d windows` (or an Android device / macOS host).

Local toolchain: `F:\Programs\flutter`, `PUB_CACHE=F:\Programs\pub-cache`, `TEMP=F:\Programs\temp`, Android SDK `F:\Programs\android-sdk`, JDK `F:\Programs\jdk17\jdk-17.0.21+9`. Windows needs Visual Studio C++ Build Tools, Windows SDK and Inno Setup 6. Flutter plugin links need Developer Mode or equivalent existing links.

`flutter build windows --release --no-pub`, then `scripts/package-windows.ps1 -SkipBuild` creates the installer and portable update ZIP with bundled Visual C++ runtime DLLs. `flutter build apk --release --no-pub` creates the Android package. Release assets live in dist/ and have SHA-256 checksums.

The GitHub workflow verifies every main-branch push. A `v*` tag builds all three targets and publishes release assets. Bump pubspec.yaml's version and build number before tagging. Android CI requires the repository's ANDROID_KEYSTORE_BASE64 secret; never commit keys or tokens.

## Verify

`flutter analyze` and `flutter test`. Use `flutter test test/wiki_live_test.dart --dart-define=LIVE_WIKI=true` to verify live wiki page parsing and the complete collection refresh. Live checks are excluded from normal offline CI because the source can rate-limit or block requests.

## Attribution

Wiki data/text: CC BY-NC-SA 4.0 (noncommercial, attribution, share alike). Game artwork © Disney/Gameloft. See ATTRIBUTION.md and each record's source links. This is not an official Disney or Gameloft application.
