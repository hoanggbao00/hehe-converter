# MediaDrop Development Rules

## Baseline

- Build with Xcode 26.3 and Swift 6.2.
- Keep deployment target at macOS 13.0 unless product requirements change.
- Use SwiftUI for settings content and AppKit for app lifecycle, menu bar, overlay windows, and drag handling.
- Keep app menu-bar-only with `LSUIElement = true`.
- Use `Makefile` targets as the project command surface: `make generate`, `make build`, `make test`, `make run`, `make open`, `make clean`.
- Keep local build products under `build/Debug`; run app only through explicit `make run`.

## Architecture

- Organize source by feature or responsibility: `App`, `MenuBar`, `Settings`, `Stores`, `Models`, `Services`.
- Keep shared observable state in `Stores`; keep `Settings` limited to settings and onboarding views.
- Keep files focused. Split only when code owns a distinct lifecycle, platform API, or test surface.
- Prefer native frameworks before dependencies. Use bundled FFmpeg only for media operations native frameworks do not cover well.
- Keep system state authoritative. Example: read launch-at-login state from `SMAppService`, not `UserDefaults`.
- Keep app-managed tools under `~/.local/com.hoanggbao.MediaDrop/bin/`.

## API Verification

- Before implementing each phase that introduces a macOS, Swift, or FFmpeg API, verify current project versions first.
- Check Apple Developer Documentation and installed SDK headers for API availability against macOS 13.0.
- Inspect bundled FFmpeg with `ffmpeg -version` and `ffmpeg -encoders` before writing command presets.
- Resolve default app-managed FFmpeg from latest stable `Tyrrrz/FFmpegBin` GitHub release at download time.
- Config version picker shows latest six stable releases with compatible macOS assets and published SHA-256 digests.
- Verify Tyrrrz release asset SHA-256 before installing downloaded FFmpeg.
- Animated WebP output must be routed through app-managed FFmpeg after verifying WebP encoder support.
- Update `docs/ffmpeg.md` when FFmpeg version, source, checksum, install path, or WebP strategy changes.
- Guard newer APIs with `#available` or avoid them when macOS 13-compatible API exists.

## Safety And Validation

- Never overwrite source media directly. Write temporary output, validate success, then move atomically.
- Do not use Accessibility UI-tree inspection or input injection. Request only permission needed for global modifier detection.
- Add focused tests for settings defaults, routing, command construction, and destructive file behavior.
- Run `make test` before handing off code changes when tests are relevant.
- Do not start a dev server automatically. Ask user when interactive runtime verification is needed.
