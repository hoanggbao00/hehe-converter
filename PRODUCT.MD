# Hehe Converter Product

Hehe Converter is a native macOS menu-bar app for converting dragged media files with configurable presets.

Idea inspired by [th2049 on X](https://x.com/th2049/status/2097015553508725184).

## Core Idea

User drags media in Finder or Desktop, holds configured shortcut key, and Hehe Converter shows a bloom-style preset picker around the pointer. Dropping on a preset converts the file without opening a full app window.

## Current Scope

- Image presets for format conversion and common image options.
- Built-in image actions for resize, crop, and compress, opened from the drag overlay.
- Resize and compress support shared `All` settings or per-image `Each` settings for multi-file drops.
- Compress previews the full-resolution result, supports original-image comparison, and keeps PNG compression lossless.
- Built-in video presets for MP4, MKV, MOV, WebM, GIF, and animated WebP; custom video presets can also target AVI, FLV, and M4V.
- Animated WebP built-in preset defaults to 24 fps.
- H.264 and HEVC video presets prefer VideoToolbox hardware encoding and fall back to matching CPU encoders.
- Multi-file drops default to parallel conversion with three concurrent jobs; both mode and limit are configurable.
- Output files are written beside input files with collision-safe suffixes such as `-1`, `-2`, `-3`.
- Conversion progress appears in a draggable compact popup.

## Settings

Settings are opened from the menu-bar item.

- General: app enable state, launch at login, conversion concurrency, and multi-file drop mode.
- Media: FFmpeg setup plus conversion preset management for image and video.
- Actions: enable built-in image actions and choose default `All` or `Each` mode for resize and compress.
- Shortcuts: shortcut recording for showing conversion presets during drag.

Portable app settings live in:

```text
~/.local/com.hoanggbao.HeheConverter/user_config.json
```

## FFmpeg

Hehe Converter uses app-managed FFmpeg for conversions native macOS APIs do not cover well, especially animated WebP.

Managed binaries live in:

```text
~/.local/com.hoanggbao.HeheConverter/bin/
```

The app can download verified prebuilt FFmpeg releases from `Tyrrrz/FFmpegBin`, or use a user-installed FFmpeg detected on the machine.

## Presets

Preset JSON files live in:

```text
~/.local/com.hoanggbao.HeheConverter/presets/image/
~/.local/com.hoanggbao.HeheConverter/presets/video/
```

Built-in presets are seeded on first launch and replaced when their seed version changes. User presets are preserved.
Image and video preset JSON currently use schema version `2`.

Video presets have two forms:

- Object presets store format and supported encoding options; Hehe Converter builds the FFmpeg command.
- Object video presets accept an optional per-preset video bitrate in kbps. Empty keeps the source bitrate; a value emits `-b:v` instead of quality rate control.
- Command presets store a user-provided FFmpeg command. Hehe Converter detects the input after `-i` and final output path, replaces them with `{input}` and `{output}`, and leaves other arguments unchanged. Editing a command preset exposes only its name and command.

## Build Product

Debug builds target the current Apple Silicon development flow:

```text
build/Debug/HeheConverter.app
```

Release builds are universal macOS apps for Apple Silicon and Intel Macs:

```text
build/Release/HeheConverter.app
```

## Non-Goals For Now

- Full media library management.
- Cloud conversion.
- Document/archive conversion.
- Accessibility-based UI automation.
