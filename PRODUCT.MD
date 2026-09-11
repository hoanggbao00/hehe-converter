# MediaDrop Product

MediaDrop is a native macOS menu-bar app for converting dragged media files with configurable presets.

Idea inspired by [th2049 on X](https://x.com/th2049/status/2097015553508725184).

## Core Idea

User drags media in Finder or Desktop, holds configured shortcut key, and MediaDrop shows a bloom-style preset picker around the pointer. Dropping on a preset converts the file without opening a full app window.

## Current Scope

- Image presets for format conversion and common image options.
- Built-in video presets for MP4, MKV, MOV, GIF, MP3, M4A, and animated WebP; custom presets can also target AVI, WebM, FLV, and M4V.
- Animated WebP built-in preset defaults to 24 fps.
- H.264 and HEVC video presets prefer VideoToolbox hardware encoding and fall back to matching CPU encoders.
- Multi-file drops support sequential or parallel conversion, with a configurable global concurrency limit.
- Output files are written beside input files with collision-safe suffixes such as `-1`, `-2`, `-3`.
- Conversion progress appears in a draggable compact popup.

## Settings

Settings are opened from the menu-bar item.

- General: app enable state, launch at login, conversion concurrency, and multi-file drop mode.
- Media: FFmpeg setup plus conversion preset management for image, video, and audio.
- Shortcuts: shortcut recording for showing conversion presets during drag.

Portable app settings live in:

```text
~/.local/com.hoanggbao.MediaDrop/user_config.json
```

## FFmpeg

MediaDrop uses app-managed FFmpeg for conversions native macOS APIs do not cover well, especially animated WebP.

Managed binaries live in:

```text
~/.local/com.hoanggbao.MediaDrop/bin/
```

The app can download verified prebuilt FFmpeg releases from `Tyrrrz/FFmpegBin`, or use a user-installed FFmpeg detected on the machine.

## Presets

Preset JSON files live in:

```text
~/.local/com.hoanggbao.MediaDrop/presets/image/
~/.local/com.hoanggbao.MediaDrop/presets/video/
~/.local/com.hoanggbao.MediaDrop/presets/audio/
```

Built-in presets are seeded on first launch and replaced when their seed version changes. User presets are preserved.

Video presets have two forms:

- Object presets store format and supported encoding options; MediaDrop builds the FFmpeg command.
- Command presets store a user-provided FFmpeg command. MediaDrop detects the input after `-i` and final output path, replaces them with `{input}` and `{output}`, and leaves other arguments unchanged. Editing a command preset exposes only its name and command.

## Build Product

Debug builds target the current Apple Silicon development flow:

```text
build/Debug/MediaDrop.app
```

Release builds are universal macOS apps for Apple Silicon and Intel Macs:

```text
build/Release/MediaDrop.app
```

## Non-Goals For Now

- Full media library management.
- Cloud conversion.
- Document/archive conversion.
- Accessibility-based UI automation.
