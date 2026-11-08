# Dreamlight Companion

Unofficial Flutter companion for Disney Dreamlight Valley on Windows, Android and macOS. English interface; SQLite data stays on your device. No account or game-save modification.

## Version 0.5.0

Companion cards now show Favorite and Liked food directly, including variant-specific Sunbird preferences. All 90 wild variants have verified food and approach data. Acquisition badges distinguish Base game / DLC, Premium Shop, paid Editions/Bundles, Star Paths, quests, crafting and events/promotions. These come from the wiki's feeding table and individual source-page revisions, not whether an animal has a wild schedule.

Recipes have Appetizers, Entrées and Desserts filters, plus their category shown on each card (95 / 227 / 158 recipes in this snapshot). Every catalog section has Mark all / Unmark all for the exact current search/category/area/progress results, with Undo. Bulk progress writes are atomic and preserve unrelated progress and daily feedings.

Selecting a planner plot exposes a separate action bar with Edit crop and Delete crop; deletion has Undo. The well remains mandatory. The planner now bundles all 58 crops/materials in the verified Gardening tables and Seeds category, including seasonal Spring V-EGG-etable and Cotton. Eight crops with plural Seeds source links were previously missed: Beetroot, Dark Chocolate Coffee Beans, Dill, Fairy Kamut, Fairy Sprinkles, Lollipop Fruit, Pearly Barley and Scarlet Kale. Their images are bundled for offline use. Temporary quest plants outside these source lists are not claimed as covered.

## Version 0.4.0

Ingredient cards display their actual zone; recipe cards show ingredients and quantities/category alternatives. The reference-table importer includes Cooking and Ingredients, with structured coverage checks before publishing.

Characters and Companions have Cards / Timetable views. The 24-hour tables keep names/locations and hour headings visible while scrolling, highlight the current configured local hour, and include Jump to now. Companion timetables offer a weekday selector and include scheduled wild variants only. All 74 character schedules come from the wiki Time table. These are published expected venues, not live tracking; a restaurant can mean Chez Remy or Tiana’s Palace, and quests/stations may override the schedule.

Companion collection filtering now uses the actual collection labels; Exhibition checklist rows no longer appear as duplicate companions. Events and Star Paths contain 50 guide records, date/status filters, and cached duty/reward text for the currently active/permanent Star Paths. Past event listings include dates and links to the source wiki.

Each planner layout contains exactly one movable, non-removable well. Existing multiple-well layouts keep the first/original well at its saved position. A JSON backup of the original layouts is written to application support before repair. Grid settings cannot crop the well out of bounds.

## Existing features

Catalog cards are compact and include item thumbnails. Main item pictures are selected from the infobox figure, rather than a small universe badge. The image cache supports original-image fallback, retry controls, paced downloads and bundled crop images. Existing cached badge images are repaired on upgrade without clearing personal progress.

Fish cards and detail panels include ripple color, weather, time, locations and other catch/unlock conditions. The offline dataset contains all 71 Fish-collection entries. If the source specifies no restriction, the interface says no restriction is listed rather than inventing a condition.

Companion cards show location, today's hours and current availability. A filter shows only companions available now, unavailable companions, or companions without a wild appearance schedule. The dataset contains 90 scheduled wild variants. Full weekly schedules use the configured game time zone, update each minute and distinguish an unknown schedule from a known absence.

Refresh downloads one shared compressed catalog from GitHub, not thousands of individual wiki requests. GitHub Actions refreshes the source tables every six hours, spaces API requests six seconds apart, limits individual detail-page refreshes to five per run, and respects Retry-After. If collection fails, the last valid published feed remains available. The wiki currently returns HTTP 403 to GitHub-hosted collection attempts; in-app refresh therefore retrieves the last published snapshot, not a guaranteed live copy of the wiki. Source freshness depends on the wiki permitting the collector. Full articles still cache when opened; bulk crawling from the client has been removed.

Farm planner: 58 bundled crop/material pictures, one movable Wishing Well per layout, floating-island bounds of 65x65 planting cells / 130x130 placement units, blocked-cell editing and collision checks. Exact biome masks have not been verified; those dimensions and blocked terrain remain manually configurable.

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
