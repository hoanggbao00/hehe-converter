# Hehe Converter

Ứng dụng macOS chạy trên menu bar để chuyển đổi ảnh, video và audio bằng thao tác kéo thả, không cần mở trình chỉnh sửa đầy đủ. Kéo file từ Finder, giữ phím tắt, rồi thả vào preset chuyển đổi hoặc action ảnh có sẵn.

[Read in English](README.en.md)

Ý tưởng lấy cảm hứng từ [th2049 trên X](https://x.com/th2049/status/2097015553508725184).

## Tính năng

- Chuyển đổi ảnh, video và audio bằng menu kéo thả dạng radial.
- Resize, crop hoặc compress ảnh với preview tương tác.
- Xử lý nhiều file tuần tự hoặc song song.
- Thêm và chỉnh preset ảnh, video, audio.
- Thêm preset lệnh FFmpeg tùy chỉnh cho video.
- Cài và xác minh FFmpeg do app quản lý trong Settings.
- Chạy gọn trong menu bar của macOS.

## Preview

### Chuyển đổi bằng preset

Kéo file được hỗ trợ từ Finder, giữ phím tắt chuyển đổi, rồi thả vào preset output.

![Preview chuyển đổi bằng preset](preview/convert.gif)

### Image actions

Kéo ảnh từ Finder, giữ `Shift` + `Option`, rồi thả vào Resize, Crop hoặc Compress.

![Preview image actions](preview/image-action.gif)

## Yêu cầu

- macOS 13.0 trở lên
- FFmpeg và FFprobe để xử lý media

Hehe Converter có thể tải bản FFmpeg tương thích ở lần mở đầu tiên. App cũng có thể nhận diện FFmpeg đã cài bằng Homebrew, MacPorts hoặc các vị trí `$PATH` được hỗ trợ.

## Cách dùng

### Chuyển đổi file

1. Mở Hehe Converter. Icon app xuất hiện trên menu bar; app không mở cửa sổ Dock.
2. Kéo một hoặc nhiều file từ Finder.
3. Trong lúc kéo, giữ `Shift` theo mặc định. Đổi phím tắt trong **Settings > Shortcuts**.
4. Di chuyển con trỏ lên preset trong menu radial.
5. Thả file để bắt đầu chuyển đổi.
6. Dùng progress panel để theo dõi hoặc hủy. Output hoàn tất nằm cạnh file gốc với tên không đè file sẵn có.

Menu preset khớp theo loại media đang kéo. Chọn lẫn ảnh, video và audio sẽ không hiện menu chuyển đổi.

### Chỉnh ảnh

1. Kéo một hoặc nhiều ảnh từ Finder.
2. Giữ `Shift` + `Option` trong lúc kéo.
3. Thả vào **Resize**, **Crop** hoặc **Compress**.
4. Chỉnh controls trong preview, rồi chọn **Apply**.

Với nhiều ảnh, Resize và Compress hỗ trợ:

- **All**: dùng chung một cấu hình cho mọi ảnh.
- **Each**: chỉnh riêng từng ảnh.

Bật/tắt action và chọn mode mặc định cho nhiều ảnh trong **Settings > Actions**.

### Quản lý preset

Mở icon menu bar, chọn **Open Settings...**, rồi vào **Media**:

- **Image**: thêm hoặc chỉnh format, resize, quality và option theo format.
- **Video**: thêm object preset hoặc preset lệnh FFmpeg tùy chỉnh.
- **Audio**: thêm hoặc chỉnh preset output audio.
- Nút folder mở nơi lưu preset JSON để kiểm tra thủ công.
- Nút refresh tải lại preset file từ disk.

Preset mặc định gồm các output ảnh phổ biến như WebP, PNG, JPG, AVIF và TIFF; output video như MP4, MKV, MOV, WebM, GIF và animated WebP; output audio như MP3, M4A, WAV, FLAC, OGG và Opus.

### Cấu hình app

Các mục trong Settings:

| Mục | Tùy chọn |
|---|---|
| General | Bật/tắt app, launch at login, số conversion song song, mode nhiều file, import/export config |
| Media | Thiết lập FFmpeg và conversion presets |
| Actions | Image actions đang bật và mode All/Each mặc định |
| Shortcuts | Phím tắt kéo thả để mở conversion preset menu |

## Tổng quan

Hehe Converter dùng SwiftUI cho Settings và action editors, AppKit cho vòng đời menu bar và overlay windows, FFmpeg cho chuyển đổi media. Bộ theo dõi drag trong Finder mở radial overlay gần con trỏ. Khi thả vào một lựa chọn, app chạy preset conversion hoặc built-in image action tương ứng.

```text
Finder drag
    |
    +-- conversion shortcut --> preset overlay --> image/video/audio runner
    |
    +-- Shift + Option -------> action overlay --> resize/crop/compress editor
                                                    |
                                                    +--> validated output beside source
```

Hành vi an toàn:

- Không bao giờ ghi đè trực tiếp source media.
- Output dùng tên khả dụng đầu tiên khi file đích đã tồn tại.
- FFmpeg chạy qua `Process` arguments, không chạy qua shell.
- FFmpeg do app quản lý phải có SHA-256 được xác minh từ release metadata.
- Output tạm được validate trước khi move sang vị trí cuối.

Dữ liệu do app quản lý nằm trong `~/.local/com.hoanggbao.HeheConverter/`:

```text
bin/                     ffmpeg, ffprobe và install metadata do app quản lý
presets/image/           Image preset JSON files
presets/video/           Video preset JSON files
presets/audio/           Audio preset JSON files
user_config.json         Portable app settings
```

## Development

### Prerequisites

- macOS 13.0 trở lên
- Xcode 26.3 với Swift 6.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Cài XcodeGen bằng Homebrew:

```sh
brew install xcodegen
```

### Commands

| Command | Mục đích |
|---|---|
| `make generate` | Tạo `HeheConverter.xcodeproj` từ `project.yml` |
| `make open` | Tạo và mở project trong Xcode |
| `make build` | Build debug app vào `build/Debug/HeheConverter.app` |
| `make test` | Tạo project và chạy XCTest suite |
| `make run` | Build và mở debug app |
| `make release` | Build universal release app cho Apple Silicon và Intel |
| `make dmg` | Build release app và đóng gói `build/Release/HeheConverter.dmg` |
| `make dmg-ci` | Đóng gói release DMG không dùng Finder UI cho CI |
| `make bump 1.0.1` | Cập nhật version, commit, tag, push và khởi chạy GitHub release |
| `make reset-onboarding` | Reset flag onboarding FFmpeg lần đầu |
| `make clean` | Xóa local build output và clean Xcode project |

`HeheConverter.xcodeproj` là file sinh từ `project.yml`. Muốn đổi cấu hình project thì sửa `project.yml`, rồi chạy `make generate`.

Hehe Converter không có hot reload. Khi test lifecycle hoặc startup, thoát app đang chạy từ menu bar trước khi chạy lại `make run`.

### Project structure

```text
Sources/
├── App/                    App lifecycle
├── DropOverlay/            Drag detection, radial menu, action editors, progress UI
├── MenuBar/                Menu-bar item và settings/onboarding windows
├── Models/                 Settings và preset models
├── Services/               FFmpeg, conversion, presets, login item, SVG rasterization
├── Settings/               SwiftUI settings sections
└── Stores/                 Shared observable state
Tests/                      XCTest coverage theo feature
docs/                       Tài liệu implementation chi tiết
preview/                    Video demo trong README
project.yml                 XcodeGen project source
Makefile                    Development command surface
```

## Documentation

- [FFmpeg integration](docs/ffmpeg.md): discovery, download, checksum verification, installation và media support.
- [Onboarding](docs/onboarding.md): trạng thái first-run FFmpeg setup và development reset.
- [Releases](docs/releasing.md): CI checks, version tags và GitHub Release artifacts.

README tập trung vào cách dùng app và entry points cho contributor. Hành vi integration và quyết định implementation chi tiết nằm trong [`docs/`](docs/).

## License

Hehe Converter được phát hành dưới [GNU General Public License v3.0](LICENSE).

Được phép dùng, sửa, fork và phân phối (kể cả thương mại). Bản phân phối phải giữ GPL-3.0 và kèm source tương ứng.
