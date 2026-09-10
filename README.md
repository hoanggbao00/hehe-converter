# MediaDrop

Native macOS menu-bar app for converting dragged media through configurable FFmpeg presets.

Idea inspired by [th2049 on X](https://x.com/th2049/status/2097015553508725184).

## Requirements

- macOS 13.0 or later
- Xcode 26.3 with Swift 6.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Development

Generate `MediaDrop.xcodeproj` from `project.yml`:

```sh
make generate
```

Open generated project in Xcode:

```sh
make open
```

Build debug app into `build/Debug/MediaDrop.app`:

```sh
make build
```

Build release app into `build/Release/MediaDrop.app`:

```sh
make release
```

Run tests:

```sh
make test
```

Build and open app:

```sh
make run
```

MediaDrop has no hot reload. Quit running app from menu-bar menu before another `make run` when testing lifecycle or startup changes.

Reset first-run FFmpeg onboarding:

```sh
make reset-onboarding
```

Remove local build output:

```sh
make clean
```

## Project Layout

```text
Sources/                 App source grouped by feature and responsibility
Tests/                   XCTest coverage
docs/                    Detailed product and implementation documentation
ref/                     Visual reference frames used during UI development
project.yml              XcodeGen project source
Makefile                 Development command surface
AGENTS.MD                Repository rules for coding agents
build/Debug/MediaDrop.app Debug build output
build/Release/MediaDrop.app Release build output
```

Generated `MediaDrop.xcodeproj` is derived from `project.yml`. Change project configuration in `project.yml`, then run `make generate`.

## Documentation

Detailed documentation lives in [`docs/`](docs/):

- [`docs/ffmpeg.md`](docs/ffmpeg.md): FFmpeg discovery, download, verification, installation, and conversion support.
- [`docs/onboarding.md`](docs/onboarding.md): first-run FFmpeg onboarding behavior and UI flow.

Keep root README focused on setup and navigation. Put feature behavior, architecture, integration flows, and implementation decisions in focused Markdown files under `docs/`.

## Local Data

MediaDrop stores managed data under `~/.local/com.hoanggbao.MediaDrop/`:

```text
bin/                     Managed ffmpeg and ffprobe binaries
presets/image/           Image preset JSON files
presets/video/           Video preset JSON files
presets/audio/           Audio preset JSON files
user_config.json         Portable app settings
```
