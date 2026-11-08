# Walkthrough: TurfService.getArenaHexagons + API danh sách Đấu trường (Module 2, NestJS)

Ngày: 4/11/2026 · Người làm: DEV 2 (có Claude hỗ trợ) · Trạng thái: chưa commit

## 1. Mục tiêu

- Sửa `GET /api/v1/turf/hexagons` cho chắc chắn: kiểm `arenaId`, báo lỗi Đấu trường không tồn tại, thêm `arenaId` vào từng ô, bọc kết quả trong `BaseResponseDto`.
- Thêm `GET /api/v1/turf/arenas`: danh sách Đấu trường đang hoạt động, kèm **số ô đếm thật** và **ranh giới GeoJSON**.
- Cập nhật client `HexagonRepository` cho định dạng mới.

## 2. Hợp đồng API

### `GET /api/v1/turf/hexagons?arenaId=<uuid>` (công khai)

| Trường hợp | Kết quả |
|---|---|
| Bỏ trống `arenaId` | 200, **toàn bộ** ô (client tải một lần, ticket #6) |
| `arenaId` đúng UUID và tồn tại | 200, chỉ các ô của Đấu trường đó |
| `arenaId` không phải UUID | 400 (`ParseUUIDPipe`), `code: "HTTP_400"` |
| `arenaId` đúng UUID nhưng không tồn tại | 404, `code: "ERR_303"`, `ARENA_NOT_FOUND: Không tìm thấy Đấu trường.` |

```json
{
  "success": true,
  "message": "Lấy trạng thái ô đất thành công.",
  "data": [
    {
      "h3Index": "8a65b56718b7fff",
      "arenaId": "b5f6…",
      "ownerUniversityId": "…",
      "universityCode": "HUTECH",
      "hexColor": "#FFCC00",
      "shieldHp": 100,
      "lastPatrolledAt": "2026-11-04T10:00:00.000Z"
    }
  ],
  "timestamp": "2026-11-04T10:00:00.000Z"
}
```

Ô trung lập: `ownerUniversityId` và `universityCode` là `null`, `hexColor` là `#44FFFFFF`. Ô chưa gán Đấu trường thì `arenaId` là `null`.

**Thay đổi phá vỡ:** trước đây `data` chính là mảng thô. Client trong repo đã được sửa theo, nhưng nếu DEV 1 có code gọi API này trên nhánh `nhan_dev1` thì cần báo họ.

### `GET /api/v1/turf/arenas` (công khai)

```json
{
  "success": true,
  "message": "Lấy danh sách Đấu trường thành công.",
  "data": [
    {
      "id": "b5f6…",
      "name": "Công Viên Landmark 81",
      "description": "Quần thể công viên ven sông Central Park",
      "hexCount": 0,
      "boundary": { "type": "Polygon", "coordinates": [[[106.7185, 10.791], "…"]] }
    }
  ],
  "timestamp": "…"
}
```

- Chỉ trả Đấu trường `is_active = true`, xếp theo tên.
- `hexCount` = số dòng trong `h3_hexagons` có `arena_id` đó (**không** dùng cột `total_hexes`, vì seed đang ghi số bịa, ticket #5). Hiện chưa nạp ô thật nên mọi Đấu trường đều là **0**; đó là kết quả đúng.
- `boundary` là GeoJSON chuẩn với thứ tự `[lng, lat]`. TypeORM tự đổi cột `geometry` sang GeoJSON khi đọc, nên không cần SQL thô.

> Một chi tiết tôi tự quyết, chưa hỏi bạn: `/hexagons?arenaId=` chỉ kiểm Đấu trường **có tồn tại**, không kiểm `is_active`. Đấu trường đã tắt vẫn xem được ô qua `arenaId`, chỉ không xuất hiện trong `/arenas`. Nếu muốn coi Đấu trường đã tắt là không tồn tại (404), chỉ cần thêm `is_active: true` vào điều kiện `exists`.

## 3. Các file thay đổi

| File | Thay đổi |
|---|---|
| `backend/src/modules/turf/turf.service.ts` | `getArenaHexagons`: kiểm Đấu trường (`ERR_303`), chuyển từ query builder sang `repository.find` có `relations`, thêm `arenaId`, dùng hằng số `NEUTRAL_HEX_COLOR`. Thêm `getArenas()`. Inject thêm repository `Arena`. |
| `backend/src/modules/turf/turf.controller.ts` | Thêm `GET arenas`; `GET hexagons` có `ParseUUIDPipe({ optional: true })`; cả hai bọc `BaseResponseDto.ok(...)`; thêm `@ApiOkResponse` và mô tả lỗi 400/404. `claim-loop` không đổi. |
| `backend/src/modules/turf/dto/turf-response.dto.ts` | **Mới.** `HexagonResponseDto`, `ArenaResponseDto`, `GeoJsonPolygonDto` và hai lớp dùng cho Swagger (`HexagonListResponseDto`, `ArenaListResponseDto`). |
| `backend/src/modules/turf/turf.module.ts` | Đăng ký `Arena` trong `TypeOrmModule.forFeature`. |
| `backend/src/entities/arena.entity.ts` | Ánh xạ cột `boundary_polygon` (`geometry(Polygon, 4326)`). Cột đã có trong `init_schema.sql`, **không cần sửa SQL**. |
| `backend/src/common/filters/all-exceptions.filter.ts` | Chỉ sửa chú thích dải mã thành `ERR_101 → ERR_303`. |
| `backend/src/modules/turf/turf.service.spec.ts` | **Mới.** 8 test. |
| `lib/src/features/map/data/hexagon_repository.dart` | Đọc `data` trong `BaseResponseDto` qua hàm `parseListPayload`; thêm `fetchArenas()` (chưa dùng ở UI). |
| `lib/src/core/errors/siso_exceptions.dart` | Thêm `SisoErrorCodes.arenaNotFound = 'ERR_303'`. |
| `test/hexagon_repository_test.dart` | **Mới.** 4 test cho `parseListPayload`. |

## 4. Cách kiểm tra

### 4.1. Test tự động

```
cd backend && npm test      # kết quả lúc tôi chạy: 17/17 pass (8 test mới)
cd .. && flutter test       # kết quả lúc tôi chạy: 18/18 pass (4 test mới)
```

Tôi cũng đã chạy `npx tsc --noEmit` (sạch), `npm run build` và `flutter build web --profile --no-tree-shake-icons --no-wasm-dry-run` (đều thành công).

Test backend mới (`turf.service.spec.ts`):

1. Bỏ trống `arenaId` thì trả toàn bộ ô và không kiểm Đấu trường.
2. Ô có chủ trả đúng mã, màu trường và `arenaId`.
3. Ô trung lập trả `null` và màu `#44FFFFFF`.
4. Có `arenaId` hợp lệ thì chỉ lọc ô của Đấu trường đó.
5. `arenaId` không tồn tại thì ném 404 `ERR_303` và không truy vấn ô.
6. `/arenas` chỉ lấy Đấu trường đang hoạt động, xếp theo tên.
7. `hexCount` là số đếm thật (seed ghi 180, kết quả 25 theo mock).
8. Thiếu mô tả hoặc ranh giới thì trả `null`.

Test client mới (`hexagon_repository_test.dart`): đọc đúng `data` khi `success = true`; `success` khác true thì rỗng; body sai dạng (kể cả **mảng thô kiểu cũ**) thì rỗng; bỏ phần tử rác.

> Các test backend dùng repository giả, nên **chưa có test nào chạy trên Postgres thật**. Riêng việc TypeORM đọc cột `geometry` thành GeoJSON chỉ kiểm được bằng tay ở mục 4.2.

### 4.2. Kiểm tay qua Swagger (`http://localhost:3000/docs`)

Chạy `cd backend && npm run start:dev` (đã kết nối Supabase), rồi:

1. **`GET /api/v1/turf/arenas`**: mong đợi 200, có 4 Đấu trường (Sala, Landmark 81, Bờ kè Thanh Đa, Khu D2) cùng các Đấu trường cũ khác nếu có trong DB. Mỗi Đấu trường có `hexCount: 0` và `boundary` là object `{ "type": "Polygon", "coordinates": [...] }`, **không phải** chuỗi WKB kiểu `0103000020E6…`. Nếu thấy chuỗi WKB thì việc ánh xạ geometry chưa chạy đúng, báo tôi.
2. **`GET /api/v1/turf/hexagons`** (bỏ trống): mong đợi 200, `data` là mảng (rỗng nếu chưa nạp ô; có 7 ô nếu bạn đã chạy SQL thử trong `walkthrough_HexagonLayer.md`).
3. **`GET /api/v1/turf/hexagons?arenaId=<id lấy ở bước 1>`**: 200, `data` rỗng (chưa có ô nào gán Đấu trường).
4. **`?arenaId=abc`**: 400.
5. **`?arenaId=00000000-0000-4000-8000-000000000000`**: 404, `code: "ERR_303"`.
6. Mục **Schemas** của Swagger hiện `HexagonListResponseDto` và `ArenaListResponseDto` đúng các trường ở mục 2.

### 4.3. Kiểm app Flutter

Chạy app như trong `walkthrough_HexagonLayer.md`. Với 7 ô thử đã nạp, bản đồ vẫn hiện đúng 7 ô sau thay đổi định dạng. Nếu bản đồ hiện "Chưa có dữ liệu ô đất" dù API trả ô, thì client đọc sai định dạng mới, báo tôi.

## 5. Checklist để bạn duyệt

- [ ] `npm test` 17/17 và `flutter test` 18/18.
- [ ] `/arenas` trả `boundary` là GeoJSON (không phải chuỗi WKB) và `hexCount` là 0.
- [ ] `/hexagons` trả 400 với `arenaId=abc`, 404 `ERR_303` với UUID không tồn tại.
- [ ] Swagger hiện đúng schema phản hồi.
- [ ] App Flutter vẫn hiện ô sau khi API đổi sang `BaseResponseDto`.
- [ ] Báo DEV 1 về thay đổi định dạng của `/hexagons`.
- [ ] Đồng ý với chi tiết tự quyết: Đấu trường đã tắt vẫn xem được ô qua `arenaId`.

## 6. Chưa làm

- Nạp ô thật của từng Đấu trường vào `h3_hexagons` và tính `total_hexes` (ticket #5 đã chốt cách làm).
- Sửa seed chồng lấn Landmark 81 và Khu D2.
- Dùng `fetchArenas()` trên UI (chọn Đấu trường, vẽ viền, căn camera).
- Bọc `BaseResponseDto` cho các endpoint khác (`claim-loop`, auth, telemetry).
- Bỏ `claimedBy` khỏi `hex_claimed` và thêm `sessionId` cho `claim-loop` (hợp đồng #3).
