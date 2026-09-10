# Onboarding

## FFmpeg Setup

MediaDrop checks app-managed FFmpeg during launch. Setup window appears only when both conditions
are true:

- `~/.local/com.hoanggbao.MediaDrop/bin/ffmpeg` is not executable.
- `didPresentFFmpegOnboarding` is not set in app `UserDefaults`.

App records `didPresentFFmpegOnboarding` when window opens, so dismissing window does not show it
again on later launches. Media settings remain available for setup afterward.

## Initial State

Window uses text-only content:

- Title: `Download FFmpeg`.
- Summary: MediaDrop uses FFmpeg for image, video, and audio conversion.
- Manual setup note tells user to copy `ffmpeg` and `ffprobe` into:

  ```text
  ~/.local/com.hoanggbao.MediaDrop/bin/
  ```

- `Open Folder` creates missing directory, opens it in Finder, then closes setup window.
- `Download` is default action. It resolves latest stable compatible GitHub release, verifies its
  published SHA-256 digest, then starts app-managed installation. Onboarding has no version picker;
  version selection lives in Media settings.

## Download State

Same window becomes progress window. It shows:

- `Installing FFmpeg`.
- Current install step on one line.
- Overall percentage.
- One progress bar.
- `Cancel`.

Internal steps are fetch, download, checksum verification, unzip, and copy. UI shows only current
step, not full step history. Window cannot close while download is active. Cancellation stops
active `URLSession` work and temporary files are removed by installer cleanup.

## Completed State

After installation and verification, same window shows:

- `Installed`.
- Installed FFmpeg version.
- Primary `OK` button.

Window remains open until user presses `OK`.

## Development Reset

Reset only onboarding presentation flag:

```bash
make reset-onboarding
```

Quit running MediaDrop before resetting and launching again. Command does not delete FFmpeg or app
settings.
