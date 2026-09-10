# FFmpeg

## Overview

MediaDrop uses app-managed FFmpeg for media operations native macOS frameworks do not cover well, including animated WebP output.

First-launch UI and state behavior live in [onboarding.md](onboarding.md).

Settings keeps FFmpeg as first section in `Config`. A `Conversion` section follows with native
segmented selection for `Image`, `Video`, and `Audio`; preset content is added there by media type.

## Install Location

App-managed binaries live under:

```text
~/.local/com.hoanggbao.MediaDrop/bin/
```

Expected files:

```text
~/.local/com.hoanggbao.MediaDrop/bin/ffmpeg
~/.local/com.hoanggbao.MediaDrop/bin/ffprobe
~/.local/com.hoanggbao.MediaDrop/bin/.mediadrop-ffmpeg.json
```

Detection checks app-managed `ffmpeg` first. If absent, it searches for a user installation beside
an already-detected binary, in Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`), MacPorts
(`/opt/local/bin`), then through the GUI process `$PATH` using `/usr/bin/env which`. Config shows
`Installed` when either app-managed or user `ffmpeg` exists, is executable, and responds to
`ffmpeg -version`; otherwise it shows `Not installed` and enables `Download`.

Typing `ffmpeg` in Terminal can find more locations because interactive shell startup files may
extend `$PATH`. A macOS GUI app does not start through that shell and usually receives a smaller
`$PATH`. `Foundation.Process.executableURL` also requires an executable file URL; it does not
resolve the bare command name `ffmpeg`. Explicit package-manager paths cover normal Homebrew and
MacPorts installs without executing user shell startup scripts.

If `.mediadrop-ffmpeg.json` exists and its repository plus installed-binary SHA-256 fingerprint
match, Config treats the install as app-managed GitHub source and shows
`Tyrrrz/FFmpegBin (<version>)` with a repository link. If metadata is missing or fingerprint no
longer matches because user replaced `ffmpeg`, Config treats it as user-managed local binary and
shows `User (<ffmpeg -version>)`.

Metadata uses JSON because fields stay explicit and schema can evolve:

```json
{
  "source": "github",
  "sourceURL": "https://github.com/Tyrrrz/FFmpegBin/releases/download/9.0.1/ffmpeg-osx-arm64.zip",
  "version": "9.0.1",
  "ffmpegSHA256": "<installed-binary-sha256>"
}
```

User-provided binary records `"source": "user"` and `"sourceURL": null`.

## Verify Flow

Config automatically verifies once when opened and installed `ffmpeg` has missing, invalid, or
stale metadata. Later visits reuse valid metadata. `Verify` runs verification manually:

1. Check app-managed folder first, then search supported user install locations and GUI `$PATH`.
2. Confirm `ffmpeg` exists and is executable.
3. Run `ffmpeg -version`; fail if binary cannot run or version cannot be parsed.
4. For app-managed folder, compute installed binary SHA-256.
5. Preserve existing source, source URL, and version when existing metadata fingerprint matches.
6. Otherwise classify binary as `User` and use detected version. External user binaries do not get
   metadata written beside them.
7. Write `.mediadrop-ffmpeg.json` atomically only for a binary inside app-managed folder.

Config displays two text columns. Rows show `Source` and `Status`, followed by conditional
verification or missing-`ffprobe` state. GitHub source links to `Tyrrrz/FFmpegBin` and includes
installed version; user-provided binaries show `User (<version>)`. Path is not shown in Config.

Actions sit below status rows. When FFmpeg is absent, Config shows `Verify`, `Open Folder`, and
`Download`. Verify checks app-managed folder first. Valid GitHub metadata keeps GitHub source;
otherwise an executable copied there by user is run to detect its version and recorded as `User`.
`Open Folder` always creates and opens MediaDrop's app-managed install folder, including when a
user FFmpeg is currently detected. Pressing `Download` fetches releases from GitHub,
then opens a version popover containing six stable releases. First item is labeled `Latest
(<version>)`; remaining items show version only. GitHub-managed installed state shows `Verify`,
`Open Folder`, and destructive `Delete`. User-managed installed state shows `Verify`, `Open
Folder`, and `Download`; it omits `Delete` so MediaDrop does not remove binaries owned by user.
Downloading while a user binary is active installs an app-managed GitHub copy in MediaDrop's bin
folder. Future detection prefers that managed copy. There is no `Re-download` action.
Delete uses native macOS confirmation with title `Delete ffmpeg & ffprobe?` and notes that binaries
can be downloaded again from Config settings.

## Release Source

MediaDrop resolves releases from GitHub at runtime:

```text
GET https://api.github.com/repos/Tyrrrz/FFmpegBin/releases?per_page=10
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

App ignores drafts, prereleases, releases without current macOS architecture asset, and assets
without GitHub `sha256:` digest. It preserves API order and takes first six compatible releases.
First release is latest and default for onboarding. Config allows choosing any returned release.

Architecture assets are `ffmpeg-osx-arm64.zip` on Apple Silicon and `ffmpeg-osx-x64.zip` on Intel.
Download URL, byte size, and SHA-256 come from selected release asset's `browser_download_url`,
`size`, and `digest` fields. MediaDrop downloads directly from GitHub, never through app server.

## Download Flow

1. Config tab calls `FFmpegInstall.isInstalled`, checking app-managed `ffmpeg` first and user
   installations second.
2. If missing, UI shows `Not installed`; no release list is fetched yet.
3. Clicking `Download` fetches releases and opens six-version picker. Selecting item chooses asset
   by compile architecture:
   - `arm64` → `ffmpeg-osx-arm64.zip`
   - other macOS builds → `ffmpeg-osx-x64.zip`
4. App creates one unique working directory under `FileManager.default.temporaryDirectory`:

   ```text
   <macOS temporary directory>/MediaDrop-FFmpeg-<UUID>/
   ```

5. `URLSession.download(from:)` first receives the response in a system temporary file. App
   moves that file into its working directory as the selected asset name and reports progress
   through `URLSessionDownloadDelegate`:

   ```text
   <macOS temporary directory>/MediaDrop-FFmpeg-<UUID>/ffmpeg-osx-<architecture>.zip
   ```

6. App computes archive SHA-256 with `CryptoKit.SHA256` and compares it with selected GitHub asset
   digest. Any mismatch stops installation.
7. App extracts verified ZIP with `/usr/bin/ditto -x -k` into temporary staging directory:

   ```text
   <macOS temporary directory>/MediaDrop-FFmpeg-<UUID>/extract/
   ```

8. App searches extracted tree for `ffmpeg` and `ffprobe`. Missing binary stops installation.
9. App creates final directory when needed, then copies both binaries from staging into:

   ```text
   ~/.local/com.hoanggbao.MediaDrop/bin/ffmpeg
   ~/.local/com.hoanggbao.MediaDrop/bin/ffprobe
   ```

10. App runs `chmod 755` on both installed binaries and refreshes Config status.
11. App writes `.mediadrop-ffmpeg.json` with selected asset URL, selected version, and installed
    `ffmpeg` SHA-256 fingerprint.
12. Swift `defer` removes entire `MediaDrop-FFmpeg-<UUID>` working directory on success or
    failure. ZIP and extracted staging files never remain in application install directory.

Installer reports these stages:

```text
Fetching release
Downloading archive
Verifying checksum
Unzipping archive
Copying binaries
```

Config and onboarding show only current stage on one line, overall percentage, and one progress
bar. They do not show full stage history. During installation, `Download` is replaced by `Cancel`.
Cancelling propagates through Swift task cancellation to active `URLSession` download, stops later
stages, and removes temporary files. After detection succeeds, Config shows:

- `Open Folder`: opens MediaDrop's app-managed bin folder in Finder.
- `Delete`: asks for confirmation, then removes app-managed `ffmpeg`, `ffprobe`, and metadata.

## Why FFprobe Stays

Keep `ffprobe` installed with `ffmpeg`. MediaDrop needs it for cheap, structured metadata reads:
duration, streams, codecs, pixel dimensions, rotation, audio layout, and output validation.
Parsing `ffmpeg` logs for that data is brittle. App-managed installs require both executables;
user-managed local binaries may omit `ffprobe`, but Config warns when it is missing.

Old installed binaries stay untouched until the new archive is downloaded, checksum-verified, and extracted successfully.

## Failure Behavior

| Failure | Result |
|---|---|
| Network/download error | Stop; show error; clean temporary working directory |
| SHA-256 mismatch | Stop before extraction; show error; clean temporary working directory |
| ZIP extraction error | Stop; show error; clean temporary working directory |
| Missing `ffmpeg` or `ffprobe` | Stop before copy; show error; clean temporary working directory |
| Final copy or `chmod` error | Stop; show error; refresh detected installation status |

## Animated WebP

Animated WebP conversion must use app-managed FFmpeg. Before enabling the user-facing conversion command, verify installed encoder support:

```bash
~/.local/com.hoanggbao.MediaDrop/bin/ffmpeg -hide_banner -encoders | grep webp
```

Expected support includes a WebP encoder such as `libwebp_anim` or equivalent WebP-capable encoder in the bundled build.

Implementation should keep WebP output behind a capability check. If the encoder is missing, hide/disable animated WebP or show a clear unsupported-binary error.
