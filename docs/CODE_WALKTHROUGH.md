# PixelCraft Code Walkthrough

เอกสารนี้อธิบายโครงสร้างและลำดับการทำงานของ PixelCraft เวอร์ชันปัจจุบัน ตั้งแต่เปิดแอป เลือกรูป สร้าง preview ปรับ filter จัดการ crop/rotate/flip/straighten ทำ undo/redo เปรียบเทียบก่อน–หลัง และ export ภาพเต็มความละเอียด

แนวคิดหลักของระบบคือ:

- Flutter รับผิดชอบ UI, interaction และ state projection
- Rust เป็น source of truth สำหรับ original image, operation history, preview rendering และ full-resolution export
- ทุกการแก้ไขถูกเก็บเป็น operation ที่ replay ได้ แทนการเก็บสำเนา PNG ทุกขั้น
- Preview ถูกจำกัดขนาดเพื่อความลื่นไหล แต่ export จะ replay operation กับ original image

---

## 1. ภาพรวมสถาปัตยกรรม

```text
Flutter UI
   ↓
EditorController / Riverpod
   ↓
ImageEngine abstraction
   ↓
flutter_rust_bridge generated bindings
   ↓
rust/src/api.rs
   ↓
EngineState + EditOperation
   ↓
filters / image transforms / encoder
```

ไฟล์หลัก:

| Layer | File | หน้าที่ |
|---|---|---|
| App startup | `lib/main.dart` | initialize Flutter และ Rust bridge |
| Home | `lib/ui/screens/home_screen.dart` | เลือกรูปจาก assets หรือ gallery |
| Editor UI | `lib/ui/screens/editor_screen.dart` | canvas, app bar, export, responsive layout |
| Tool controls | `lib/ui/widgets/editor_tool_panel.dart` | Adjust, Filters, Crop, Rotate, Details |
| State | `lib/state/editor_controller.dart` | editor commands และ state projection |
| Dart engine boundary | `lib/core/image_engine.dart` | abstraction ระหว่าง Flutter กับ FRB |
| Export file I/O | `lib/core/export_file_service.dart` | save และ share exported file |
| Rust API | `rust/src/api.rs` | function ที่ expose ผ่าน FRB |
| Rust session engine | `rust/src/engine.rs` | original bytes, operations, cursor และ replay |
| Filters | `rust/src/filters.rs` | core filters |
| Creative filters | `rust/src/photon_filters.rs` | creative presets |

---

## 2. Startup และ Rust bridge

### `lib/main.dart`

จุดเริ่มต้นเรียก `WidgetsFlutterBinding.ensureInitialized()` และสร้าง `ProviderScope` เพื่อให้ Riverpod providers ใช้งานได้ทั่วแอป

แอปไม่ควร block เฟรมแรกด้วย native initialization โดยไม่มี fallback จึงมี bootstrap screen ที่:

1. เรียก `initializeRustBridge()`
2. แสดง loading state
3. เปิด `HomeScreen` เมื่อสำเร็จ
4. แสดง error และ Retry เมื่อ native library โหลดไม่สำเร็จหรือ timeout

### `lib/core/bridge.dart`

`initializeRustBridge()` ครอบ `RustLib.init()` ซึ่งมาจาก FRB-generated bindings

กลไกสำคัญ:

- ป้องกัน initialization ซ้ำ
- แชร์ Future เดียวกันเมื่อมีหลาย caller
- reset Future เมื่อ initialization ล้มเหลว เพื่อให้ Retry ทำงานจริง

เมื่อ Rust API เปลี่ยน ต้องรัน:

```bash
make codegen
```

ไฟล์ generated ใน `lib/src/rust/` และ Rust bridge code ต้องถูก commit หลังตรวจสอบแล้ว

---

## 3. การเลือกรูปจาก Home

### `lib/ui/screens/home_screen.dart`

ผู้ใช้เลือกรูปได้จาก:

- sample assets
- device gallery ผ่าน `image_picker`

Home อ่าน compressed image bytes แต่ไม่ decode ใน Dart จากนั้นส่ง bytes เข้า `EditorScreen`:

```dart
EditorScreen(imageBytes: bytes)
```

การไม่ decode รูปใน Dart ช่วยให้ ownership ของ image-processing pipeline อยู่ใน Rust อย่างชัดเจน

---

## 4. การโหลด image session

### `EditorScreen.initState()`

เมื่อเปิดหน้า Editor จะเรียก:

```dart
Future.microtask(
  () => ref.read(editorProvider.notifier).load(bytes),
);
```

ใช้ microtask เพื่อหลีกเลี่ยงการเปลี่ยน provider ระหว่าง widget tree กำลัง build

### `EditorController.load()`

ลำดับคือ:

```text
loadImage(original bytes)
preparePreview(maxEdge: 1280)
originalPreview()
getHistogram(preview)
sessionInfo()
```

### `rust/src/api.rs::load_image()`

Rust decode ภาพเพื่อตรวจสอบว่า bytes ถูกต้อง แล้วเรียก:

```rust
ENGINE.lock()?.reset(bytes)
```

### `EngineState.reset()`

รีเซ็ต session เป็น:

```text
original = compressed source bytes
operations = []
cursor = 0
preview_max_edge = 1280
pending transaction = none
```

Original bytes ไม่ถูกแทนที่ด้วย preview และไม่ถูก encode ซ้ำในขั้นนี้

---

## 5. Operation-based editing model

### `rust/src/engine.rs::EditOperation`

ทุกการแก้ไขถูกเก็บเป็น enum:

```rust
pub enum EditOperation {
    Filter { name: String, value: f32 },
    Crop { x: f32, y: f32, width: f32, height: f32 },
    Rotate90 { turns: u8 },
    RotateDegrees { degrees: f32 },
    FlipHorizontal,
    FlipVertical,
    Resize { width: u32, height: u32 },
}
```

จุดสำคัญ:

- Crop ใช้ normalized coordinates ช่วง `0.0..1.0`
- Rotate90 เก็บจำนวน quarter turns
- Straighten เก็บเป็นองศา
- Resize เก็บ output dimensions
- Filter เก็บชื่อและค่า intensity

Operation เหล่านี้ใช้ทั้ง preview, undo/redo และ export จึงไม่มี editing model สองชุด

### `EngineState`

State หลักใน Rust:

```text
original
operations
cursor
preview_max_edge
preview_base
pending_operation
pending_preview
active_filter
```

`cursor` คือจำนวน operation ที่ active อยู่

ตัวอย่าง:

```text
operations = [brightness, crop, rotate, vintage]
cursor = 2
```

หมายถึงภาพปัจจุบันใช้เฉพาะ `brightness` และ `crop` ส่วน `rotate` กับ `vintage` เป็น redo items

---

## 6. Preview rendering

### `prepare_preview()`

Dart ส่ง `maxEdge: 1280` ไป Rust

Rust เก็บค่าใน `preview_max_edge` แล้วเรียก `render_preview()`

### `render_preview_image()`

ขั้นตอน:

1. decode original bytes
2. replay active operations ตั้งแต่ index `0` ถึง `cursor - 1`
3. ตรวจด้านยาวของภาพ
4. ถ้าเกิน `preview_max_edge` ให้ resize ด้วย Lanczos3
5. encode preview เป็น PNG

จึงต่างจากระบบเดิมที่เก็บ preview PNG เป็น history โดยตรง

Preview มีหน้าที่เพื่อ UI เท่านั้น ส่วน original image และ operation list ยังคงอยู่ใน Rust

---

## 7. Filter transaction

Filter slider ต้องไม่สร้าง operation ทุก pointer event จึงใช้ transaction สามขั้น

### 7.1 `beginAdjustment()`

Flutter เรียก:

```dart
_engine.beginFilter(state.selectedFilter)
```

Rust เรียก `begin_filter()` และสร้าง `preview_base` จาก committed operations ปัจจุบัน

ภาพฐานนี้คงที่ตลอด gesture

### 7.2 `previewValue()`

เมื่อ slider เปลี่ยนค่า:

```dart
final result = _engine.updateFilterPreview(filter, value)
```

Rust:

1. clone `preview_base`
2. apply filter ด้วยค่าล่าสุด
3. encode PNG preview
4. เก็บ `pending_operation`
5. เก็บ `pending_preview`
6. ส่ง bytes และ elapsed time กลับ Dart

ทุก tick จึงประมวลผลจาก base เดิม ไม่ได้นำผล tick ก่อนหน้ามาปรับซ้ำ

### 7.3 `commitAdjustment()`

เมื่อปล่อย slider:

```dart
_engine.commitFilter()
```

Rust push `pending_operation` เพียงรายการเดียวลง history

ถ้าผู้ใช้ลากผ่าน 20 ค่า แต่ปล่อยครั้งเดียว จะเกิดเพียงหนึ่ง committed operation

### `FilterSlider`

Widget throttle callback ประมาณหนึ่งครั้งต่อ frame เพื่อไม่เรียก Rust ทุก pointer event แต่ UI thumb ยังเคลื่อนทันทีด้วย local state

---

## 8. Crop, Rotate, Flip และ Straighten

### Dart boundary: `ImageEngine`

เพิ่ม methods:

```dart
applyCrop(...)
rotateQuarterTurns(turns)
straighten(degrees)
flipHorizontal()
flipVertical()
resizeCommitted(...)
```

`RustImageEngine` แปลง call เหล่านี้ไปยัง generated FRB functions

### Rust API

`rust/src/api.rs` expose:

```text
apply_crop
rotate_quarter_turns
straighten
flip_horizontal
flip_vertical
resize_committed
```

ทุก method สร้าง `EditOperation` แล้วเรียก:

```rust
engine.apply_operation(operation)
```

### `apply_operation()`

ขั้นตอน:

1. clear filter transaction ที่ค้าง
2. truncate operations หลัง cursor
3. push operation ใหม่
4. เลื่อน cursor ไปท้าย list
5. render preview ใหม่

ดังนั้น transform ทุกตัว undo/redo ได้ และ commit หลัง undo จะลบ redo branch ตามพฤติกรรม editor ปกติ

### Crop presets

`EditorController.applyCenteredCrop()` คำนวณ normalized crop rectangle จาก aspect ratio

ตัวอย่าง `1:1`:

```text
width = 1.0
height = 1.0
x = 0.0
y = 0.0
```

สำหรับ landscape ratio เช่น `16:9` จะลด normalized height และจัดให้อยู่กึ่งกลาง

Preset ปัจจุบัน:

- 1:1
- 4:3
- 3:4
- 16:9
- 9:16

### Straighten

Straighten จำกัดค่า `-15°..15°`

Rust ใช้ `imageproc::geometric_transformations::rotate_about_center` แบบ bilinear interpolation และเติมพื้นที่ว่างด้วย transparent pixels

ค่าที่ใกล้ `0°` จะไม่สร้าง operation เพื่อหลีกเลี่ยง no-op history entry

---

## 9. Undo และ Redo

### `SessionSnapshot`

Rust ส่ง state summary ผ่าน `session_info()`:

```text
version
operation_count
cursor
can_undo
can_redo
```

Dart map เป็น `EngineSessionInfo`

### Undo

```rust
cursor = cursor.saturating_sub(1)
render_preview()
```

ไม่มีการลบ operation ออกจาก list

### Redo

```rust
if cursor < operations.len() {
    cursor += 1;
}
render_preview()
```

### Controller projection

หลัง command ทุกตัว `_applyCommittedPreview()` จะ refresh:

- preview bytes
- histogram
- operation count
- cursor
- canUndo
- canRedo

AppBar แสดง:

```text
Editor · 3/5 edits
```

หมายถึง active 3 operations จากทั้งหมด 5 รายการ

---

## 10. Before / After comparison

ตอน load controller ขอ `originalPreview()` จาก Rust และเก็บใน `originalPreviewBytes`

`EditorState.visiblePreview` เลือก:

```dart
showOriginal
  ? originalPreviewBytes ?? previewBytes
  : previewBytes
```

`EditorScreen` ใช้ long press บน canvas:

- `onLongPressStart` → แสดง original
- `onLongPressEnd` → กลับ edited preview
- `onLongPressCancel` → reset state

Chip คำว่า `Original` แสดงผ่าน `AnimatedOpacity`

Original preview ถูกสร้างหนึ่งครั้งตอน load ไม่ได้ decode ใหม่ทุกครั้งที่กดค้าง

---

## 11. Tool-based Editor UI

### `EditorTool`

```dart
enum EditorTool {
  adjust,
  filters,
  crop,
  rotate,
  details,
}
```

### `EditorToolPanel`

ใช้ `SegmentedButton` สำหรับเลือก tool

#### Adjust

แสดง core filters และ slider ช่วง `0..2`

#### Filters

แสดง creative filters แบบ horizontal list และ slider ช่วง `0..1`

#### Crop

แสดง aspect-ratio presets

#### Rotate

มี:

- rotate left
- rotate right
- flip horizontal
- flip vertical
- straighten slider

#### Details

แสดง histogram, Rust processing time และ operation cursor

Tool navigation ถูกห่อด้วย horizontal scroll เพื่อไม่ overflow บนโทรศัพท์จอแคบ

---

## 12. Responsive Editor layout

`EditorScreen` ใช้ `LayoutBuilder`

### Width ต่ำกว่า 900 px

```text
AppBar
Canvas
Tool panel ด้านล่าง
```

เหมาะกับ phone และ small tablet

### Width ตั้งแต่ 900 px

```text
AppBar
Canvas                         Tool panel
                               fixed width 360
```

Canvas ใช้พื้นที่ flex 3 ส่วน และ tool panel อยู่ด้านขวา

การแยก layout นี้ช่วยให้ tablet ไม่ต้องบีบ controls ไว้ใต้ภาพ และลด vertical scrolling

---

## 13. Histogram และ performance information

`get_histogram()` decode preview เป็น RGBA และใช้ Rayon ประมวลผลแบบ parallel

ผลลัพธ์มี 768 bins:

```text
0..255     Red
256..511   Green
512..767   Blue
```

Histogram คำนวณจาก preview ไม่ใช่ full-resolution original เพื่อควบคุม latency

`ProcessedImage.elapsed_micros` เป็น `u64` ใน Rust และถูก map เป็น `BigInt` ใน Dart

Controller แปลงเป็น milliseconds:

```dart
result.elapsedMicros.toDouble() / 1000.0
```

ค่าดังกล่าวเป็นเวลาที่ Rust ใช้ประมวลผลและ encode preview ไม่ใช่ frame rendering time ทั้งหมดของ Flutter

---

## 14. Full-resolution export

### `EditorController.exportImage()`

รับ:

```text
format
quality
```

แล้วเรียก Rust ผ่าน `ImageEngine`

### `rust/src/api.rs::export_image()`

ขั้นตอน:

1. lock engine
2. decode original image
3. replay active operations ถึง cursor
4. encode ตาม format

รองรับ:

- PNG
- JPEG/JPG พร้อม quality `1..100`
- WebP

Export ไม่ใช้ `previewBytes` จึงไม่สูญเสีย resolution จาก preview limit 1280 px

Crop, filter, rotate, flip และ straighten ถูก replay ด้วย pipeline เดียวกับ preview

### `ExportFileService`

รับ bytes จาก Rust แล้ว:

1. หา application documents directory
2. สร้างชื่อไฟล์ตาม timestamp
3. เขียน bytes ลง disk
4. ส่ง file path กลับ UI
5. แชร์ผ่าน system share sheet เมื่อผู้ใช้เลือก Share

ปัจจุบันเป็น save-to-app-documents + share ยังไม่ใช่ direct insertion เข้า Android Gallery หรือ iOS Photos

---

## 15. Error handling

Controller ครอบ engine calls ด้วย `try/catch` และ project error เป็น string ใน `EditorState.error`

กรณีสำคัญ:

- image decode ล้มเหลว
- engine mutex poisoned
- invalid crop size
- invalid resize dimensions
- straighten เกินช่วง
- unsupported export format
- file write/share ล้มเหลว

UI แสดง load error กลางหน้าจอ และ export error ผ่าน `SnackBar`

---

## 16. Test strategy

### Rust unit tests

ตรวจ:

- slider gesture สร้าง operation เดียว
- transform operations replay ได้
- undo/redo เลื่อน cursor
- commit ใหม่หลัง undo ลบ redo branch
- crop bounds และ resize validation

### Controller tests

ใช้ `FakeImageEngine` เพื่อทดสอบ:

- load original/preview/histogram
- filter transaction
- operation cursor
- crop/rotate/flip/straighten
- tool selection
- undo/redo
- before/after
- export

### Widget tests

ตรวจ:

- Editor load สำเร็จ
- filter gesture เรียก begin/preview/commit
- Undo/Redo enabled ตาม session state
- dynamic AppBar title
- tool interactions

### Golden tests

ครอบคลุมอย่างน้อย:

- Home phone
- Editor phone
- Export dialog
- Before comparison

เมื่อ UI layout เปลี่ยนต้องรัน:

```bash
make golden-update
make golden-test
```

และ review ภาพ baseline ก่อน commit

### Native integration test

ทดสอบบน device จริงเพื่อยืนยันว่า:

- Rust shared library ถูก bundle
- FRB init สำเร็จ
- native API เรียกได้
- image processing คืนค่าถูกต้อง

---

## 17. Validation workflow

หลังแก้ Rust API หรือ operation schema:

```bash
flutter pub get
make codegen
cargo fmt --manifest-path rust/Cargo.toml --all
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make golden-update
make golden-test
make verify-native
make native-test DEVICE=RF8Y909V0LV
```

Generated files, lockfile และ golden baselines ที่เปลี่ยนควรถูกตรวจ diff และ commit ใน feature branch เดียวกัน

---

## 18. ข้อจำกัดปัจจุบัน

- Rust calls ส่วนใหญ่ยังเป็น synchronous bridge calls
- Straighten commit ตอนปล่อย slider ยังไม่มี live native preview ระหว่างลาก
- Crop ปัจจุบันเป็น centered presets ยังไม่มี interactive crop handles
- Direct save เข้า Gallery/Photos ยังไม่มี
- Tablet breakpoint ใช้ fixed threshold 900 px
- Session ยังไม่ persist หลัง process ถูก kill
- ยังไม่มี stale-request protection สำหรับ async preview pipeline

ข้อจำกัดเหล่านี้เป็นจุดต่อยอดสำหรับ async rendering, draft recovery, interactive crop และ production-quality media saving ในลำดับถัดไป
