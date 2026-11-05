# Walkthrough: HexagonLayer (Module 2, Flutter)

Ngày: 4/11/2026 · Người làm: DEV 2 (có Claude hỗ trợ) · Trạng thái: chưa commit

## 1. Mục tiêu

Vẽ lưới ô lục giác H3 res 10 lên bản đồ thật, theo các quyết định đã chốt:

- Tải **toàn bộ ô một lần** qua `GET /api/v1/turf/hexagons` (chưa lọc theo Đấu trường), giữ sẵn ranh giới ô (ticket wayfinder #6, cách A).
- **Không dùng Isolate** cho việc chuyển đổi H3 (ticket #6).
- Sự kiện `hex_claimed` chỉ đổi chủ và màu của các ô đã tải, theo payload ở hợp đồng #3: `{ universityId, universityCode, hexColor, claimedHexes, arenaId, claimedAt }`.
- Tile nền tạm dùng OpenStreetMap, vì Carto đòi API key (ticket #16 chưa chốt).

## 2. Luồng chạy

```
main() ── SocketManager.initialize()
   │
MapScreen
   └─ FlutterMap (tâm 10.800, 106.718, zoom 15)
        ├─ TileLayer (AppConstants.mapTileUrl = OSM)
        ├─ HexagonLayer ──watch──► mapStateNotifierProvider
        │                              │ lần đầu được đọc:
        │                              ├─ loadHexagons()  ── HexagonRepository.fetchArenaHexagons() ── GET /turf/hexagons
        │                              │      └─ mỗi dòng → HexCell (màu, chủ, shieldHp, ranh giới qua h3BoundaryOf)
        │                              └─ subscribeRealtime() ── SocketManager.onHexClaimed(applyHexClaimed)
        └─ SimpleAttributionWidget ("OpenStreetMap contributors", bắt buộc theo chính sách OSM)
```

`HexagonLayer` đổi mỗi `HexCell` thành một `Polygon`:

| Loại ô | Màu tô | Viền |
|---|---|---|
| Có chủ (`universityId` khác null) | màu trường, độ đậm 0,45 | `black26`, 1px |
| Trung lập | trắng, độ đậm 0,35 | `black26`, 1px |

Nếu chưa có ô nào (API rỗng, lỗi mạng hoặc đang tải), bản đồ hiện nhãn **"Chưa có dữ liệu ô đất"** ở đáy.

> **Lệch nhẹ so với lúc thống nhất:** ta đã thống nhất "trắng rất mờ, viền mảnh". Nhưng tile OSM tạm thời là nền **sáng**, nên tôi tăng độ đậm ô trung lập lên 0,35 và dùng viền tối (`black26`) để ô còn nhìn thấy được. Khi #16 chốt tile nền tối thì chỉnh lại hằng số `HexagonLayer.neutralAlpha` và màu viền.

## 3. Các file thay đổi

| File | Thay đổi |
|---|---|
| `lib/src/features/map/domain/hex_cell.dart` | **Mới.** Kiểu `HexCell` và hàm `parseHexColor` (nhận `#RRGGBB` và `#AARRGGBB`, sai định dạng thì trả màu trung lập). |
| `lib/src/features/map/domain/h3_boundary.dart` | **Mới.** `h3BoundaryOf`: chuỗi H3 → các đỉnh lục giác. Thư viện H3 chỉ nạp khi dùng lần đầu. |
| `lib/src/features/map/providers/map_state_notifier.dart` | **Viết lại.** State từ `Map<String, String>` thành `Map<String, HexCell>`. Thêm `loadHexagons`, `applyHexClaimed`, `subscribeRealtime`, `hexagonRepositoryProvider`. Bỏ `updateHexOwner` (stub, không nơi nào dùng). |
| `lib/src/features/map/presentation/hexagon_layer.dart` | **Viết lại.** `ConsumerWidget` vẽ `PolygonLayer`, kèm nhãn khi rỗng. |
| `lib/src/features/map/presentation/map_screen.dart` | **Sửa.** Thêm `FlutterMap`, tile, camera ban đầu, ghi nguồn OSM. `HexagonLayer` nằm trong bản đồ. |
| `lib/src/core/constants/app_constants.dart` | **Sửa.** Thêm `mapTileUrl`. |
| `test/map_state_notifier_test.dart` | **Mới.** 11 test cho `MapStateNotifier` với repository giả. |

Các file sửa từ trước (prototype #6, chưa commit) vẫn còn: `web/index.html` (script h3-js, **cần cho màn này chạy trên Chrome**), `pubspec.lock`, hai file `prototype_hex_perf`.

## 4. Cách kiểm tra

### 4.1. Test tự động

```
flutter test
```

Kết quả lúc tôi chạy: **14/14 pass**, gồm 11 test mới, 2 test Kalman cũ và 1 widget test. Các dòng `ClientException ... status 400` trong widget test là do `flutter test` chặn mạng nên tile nền không tải được. Chúng không làm test fail.

Các trường hợp test mới bao phủ:

1. Tải toàn bộ ô kèm ranh giới và `shieldHp`.
2. Ô có chủ mang màu trường; ô `ownerUniversityId = null` là trung lập.
3. Đọc được `#AARRGGBB`; màu sai định dạng thành màu trung lập.
4. Bỏ qua dòng thiếu `h3Index`.
5. Backend rỗng hoặc lỗi thì không có ô nào.
6. `hex_claimed` đổi chủ, màu, và hồi `shieldHp` về 100 đúng các ô được chiếm.
7. Ô không có trong sự kiện giữ nguyên.
8. Ô chưa có trên bản đồ bị bỏ qua, không bị thêm vào.
9. Payload sai định dạng bị bỏ qua.
10. Sự kiện đi qua `subscribeRealtime` cập nhật bản đồ.
11. Sự kiện đến sau khi notifier bị huỷ không gây lỗi.

> Kiểm tra tĩnh: `flutter analyze` không có warning hay error, chỉ còn 4 mục `info` có từ trước ở `socket_manager.dart` và `percent_dominance_bar.dart`, không liên quan thay đổi này. (Lúc viết ban đầu, lệnh này bị lỗi vì đường dẫn repo có chữ "Đ"; thư mục đã được đổi tên nên lỗi không còn.)

### 4.2. Chạy app, khi chưa có dữ liệu

```
cd backend && npm run start:dev      # terminal 1
flutter run -d chrome                 # terminal 2, ở thư mục gốc repo
```

Mong đợi: bản đồ OSM quanh D2/Landmark 81, ghi nguồn "OpenStreetMap contributors" ở góc, nhãn **"Chưa có dữ liệu ô đất"** ở đáy (vì `h3_hexagons` chưa có dòng nào).

### 4.3. Chạy app, có dữ liệu thử

Chạy SQL sau trong Supabase (SQL Editor). Đây là **dữ liệu thử**: 7 ô quanh tâm bản đồ, sinh bằng `h3-js` `gridDisk(latLngToCell(10.800, 106.718, 10), 1)`.

```sql
-- DỮ LIỆU THỬ cho walkthrough HexagonLayer: xoá sau khi kiểm tra
INSERT INTO public.h3_hexagons (h3_index, owner_university_id, shield_hp)
VALUES
  ('8a65b56718b7fff', (SELECT id FROM public.universities WHERE short_code = 'HUTECH'), 100),
  ('8a65b5671d6ffff', (SELECT id FROM public.universities WHERE short_code = 'HUTECH'), 100),
  ('8a65b5671d4ffff', (SELECT id FROM public.universities WHERE short_code = 'UEF'),    100),
  ('8a65b5671897fff', NULL, 100),
  ('8a65b5671887fff', NULL, 100),
  ('8a65b56718a7fff', NULL, 100),
  ('8a65b567199ffff', NULL, 100)
ON CONFLICT (h3_index) DO NOTHING;
```

Tải lại app. Mong đợi: một cụm 7 lục giác ở giữa màn hình, 2 ô vàng (HUTECH), 1 ô đỏ (UEF), 4 ô trung lập; nhãn "Chưa có dữ liệu" biến mất.

Xoá dữ liệu thử:

```sql
DELETE FROM public.h3_hexagons WHERE h3_index IN
  ('8a65b56718b7fff','8a65b5671d6ffff','8a65b5671d4ffff','8a65b5671897fff',
   '8a65b5671887fff','8a65b56718a7fff','8a65b567199ffff');
```

### 4.4. Kiểm tra realtime (`hex_claimed`)

Giữ app đang mở, làm trên Swagger (`http://localhost:3000/docs`):

1. `POST /api/v1/auth/edu-login` với `{ "email": "<tên>@uef.edu.vn" }`.
2. `POST /api/v1/auth/verify-otp` với email đó và `"otp": "123456"`, rồi copy `accessToken` vào nút **Authorize**.
3. `POST /api/v1/turf/claim-loop` với:
   ```json
   {
     "boundaryH3Indexes": ["8a65b5671897fff", "8a65b5671887fff", "8a65b56718a7fff"],
     "distanceMeters": 500,
     "durationSeconds": 180
   }
   ```

Mong đợi: 3 ô trung lập đó **đổi sang màu đỏ UEF ngay** trên app mà không cần tải lại.

Cần biết khi kiểm bước này:
- Backend hiện vẫn gửi `claimedBy` trong `hex_claimed`. Hợp đồng #3 đã quyết bỏ nhưng chưa sửa backend. Client bỏ qua trường đó.
- `claim-loop` hiện **chưa** đòi `sessionId` như hợp đồng #3, nên gọi thẳng được.
- `H3Service` đang đảo trục lat/lng (đã ghi trên bản đồ wayfinder), nên ô "bên trong" vòng có thể bị tính sai. Ô nào không có trên bản đồ thì client bỏ qua, đúng thiết kế. Bạn chỉ cần xác nhận 3 ô biên đổi màu.
- Bước này ghi thêm km vào trường UEF và tài khoản thử. Nếu cần sạch dữ liệu thì xoá dòng trong `running_sessions` và trừ lại km.

## 5. Checklist để bạn duyệt

- [ ] `flutter test` pass 14/14.
- [ ] Mở app khi chưa có dữ liệu: thấy bản đồ OSM và nhãn "Chưa có dữ liệu ô đất".
- [ ] Sau SQL thử: thấy 7 ô, đúng màu HUTECH/UEF/trung lập, đúng vị trí quanh D2/Landmark 81.
- [ ] Kéo, zoom bản đồ: các ô dính đúng vị trí, không giật bất thường.
- [ ] Claim-loop qua Swagger: 3 ô đổi màu UEF ngay, không cần tải lại.
- [ ] Đọc `map_state_notifier.dart` và `hexagon_layer.dart`: tên và chú thích dễ hiểu với bạn.

## 6. Chưa làm (theo phạm vi đã thống nhất)

- Animation Pulse khi đổi màu (Module 6).
- Độ mờ ô theo `shieldHp` (nằm trong danh sách cắt khi trễ).
- Lọc theo Đấu trường và API danh sách Đấu trường (chưa có ở backend).
- Nạp ô thật của các Đấu trường vào `h3_hexagons` (ticket #5 đã chốt cách làm).
- Căn camera theo GPS người dùng (việc DEV 1 hỗ trợ).
- Đo FPS trên iPhone (Milestone 1).
