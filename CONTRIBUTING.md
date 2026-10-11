# Contributing to NAIWeaver

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. Install Flutter (stable channel, SDK ^3.10.7)
2. Clone the repository
3. Run `flutter pub get`
4. Run `flutter run -d windows` (or `-d chrome` for web)

## Code Style

- Follow existing patterns in the codebase
- Use `flutter analyze` before submitting — no new warnings
- Format with `dart format lib/`
- State management uses Provider + ChangeNotifier — keep that pattern
- Feature code goes in `lib/features/{name}/` with `models/`, `providers/`, `services/`, `widgets/` sub-folders
- ML processing code goes in `lib/core/ml/`
- Tools Hub features go in `lib/features/tools/{tool_name}/` (e.g., `director_tools/`, `enhance/`, `ml/`)
- Shared utilities go in `lib/core/` (services, utils, widgets)

## UI conventions check

`scripts/check_ui_conventions.sh` counts violations of the rules in
[ARCHITECTURE.md](ARCHITECTURE.md) ("UI Conventions") per file under `lib/`
(`Colors.*`, `Color(0x`, numeric `fontSize:`, `Theme.of(context).colorScheme`,
direct `showModalBottomSheet(` / `SnackBar(`, `MediaQuery` width compared to a
number) and compares them with `scripts/ui_conventions_baseline.txt`.

- It exits 1 and names the file, category and increase when any count goes up
  or a clean file gains a violation. Fix the code; do not raise the baseline.
- When counts go down it says so; run `scripts/check_ui_conventions.sh --update`
  and commit the new baseline so the improvement is locked in.
- `.github/workflows/ci.yml` runs it, `flutter analyze`, `flutter test`, the
  Chrome browser tests, `node --test test/web/*.test.mjs` and the gateway unit
  tests (Flutter pinned to 3.44.8) on every push to `master` and every pull
  request.

## Tests

Tests cover critical paths only: billing and quotes, the auth session
lifecycle, request building against the gateway whitelist, generation state,
history access, data round-trips, and crash or data-loss guards. Don't add
tests that restate an implementation, fake away the logic under test, or only
assert layout.

- `flutter test` — VM suite
- `flutter test --platform chrome test/browser_native_text_area_test.dart test/browser_platform_view_lifecycle_test.dart` — DOM-backed web widgets (skipped on the VM)
- `node --test test/web/*.test.mjs` — PhotoSwipe bridge key policy
- `cd server && NAIWEAVER_DATA_DIR=$(mktemp -d) uv run python -m unittest discover -s tests` — gateway; never point tests at the production data directory
- `test/fixtures/quote_cases.json` and `test/fixtures/image_request_keys.json` are shared by the gateway and Flutter suites; change them together with `docs/GATEWAY_CONTRACT.md`

## Pull Request Process

1. Fork the repository and create a branch from `master`
2. Make your changes with clear, focused commits
3. Ensure `flutter analyze` passes with no new issues
4. Update documentation if adding new features
5. Open a PR with a clear description of what changed and why

## Feature Requests

Feature requests are welcome! Please open a [GitHub Issue](../../issues) with the `enhancement` label. Include:

- A clear description of the feature and the problem it solves
- Any reference to NovelAI API capabilities it would use
- Mockups or examples if applicable

Check the [ROADMAP.md](ROADMAP.md) for planned features — your idea might already be on the list.

## Localization

NAIWeaver supports multiple languages via Flutter's ARB localization system. To add a new language:

1. Copy `lib/l10n/app_en.arb` to `lib/l10n/app_XX.arb` (where `XX` is the language code, e.g., `ko`, `de`)
2. Translate all string values in the new `.arb` file
3. Run `flutter gen-l10n` (or let `flutter run` regenerate automatically) to create `app_localizations_XX.dart`
4. In `lib/l10n/app_localizations.dart`: add the import, add `Locale('XX')` to `supportedLocales`, and add the `case 'XX'` in `lookupAppLocalizations`
5. Add a `DropdownMenuItem` for the new locale in `lib/features/tools/widgets/app_settings.dart`
6. Add `if (lang == 'XX')` handling in `lib/core/l10n/locale_notifier.dart`
7. Add locale matrix entries in `.github/workflows/release.yml`
8. Test the new language by switching locale in **TOOLS > SETTINGS**

Existing languages: English (`en`), Japanese (`ja`), Simplified Chinese (`zh`).

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include steps to reproduce for bugs
- Include platform info (Windows/Android/Web) and Flutter version
- Screenshots or error logs are helpful

## Architecture Notes

See [ARCHITECTURE.md](ARCHITECTURE.md) for a detailed breakdown of the codebase structure, data flow, and design decisions.
