# Ranh giới 3 Đấu trường: nguồn toạ độ và cách biểu diễn (ticket #5)

Ngày điều tra: 2026-11-04. Liên quan: issue #2 (bản đồ), #5 (ticket này).

## Kết luận ngắn

1. **Nguồn toạ độ**: OpenStreetMap (qua Nominatim / OSM API v0.6; dữ liệu ODbL, cần ghi "© OpenStreetMap contributors"). Sala và Vinhomes Central Park (Landmark 81) có polygon trong OSM; **"Bờ kè Thanh Đa" không có polygon riêng**, chỉ có một công viên nhỏ (khoảng 1 ô H3) và các đường `Thanh Đa`, nên phải tự vẽ polygon.
2. **Biểu diễn**: giữ **polygon PostGIS làm ranh giới gốc** (`arenas.boundary_polygon`, đã có trong schema), **đồng thời nạp sẵn tập ô H3 res 10 vào `h3_hexagons`** (`arena_id` đã là FK). Lý do: server cần tra "ô này thuộc Đấu trường nào" theo khoá chính `h3_index` (O(1)), còn polygon dùng để hiển thị, kiểm tra điểm GPS nằm trong Đấu trường (GiST index sẵn có) và để sinh lại ô khi đổi ranh giới. Chỉ lưu tập ô H3 thì mất ranh giới chính xác; chỉ lưu polygon thì phải `ST_Contains` cho mỗi ô/mỗi điểm.
3. **Số ô H3 res 10**: mỗi Đấu trường chỉ khoảng 25 đến 60 ô (xem bảng), **dưới trần 150 ô/vòng claim** ngay cả khi claim cả Đấu trường. Số `total_hexes` trong seed hiện tại (250/180/120) **sai**, nên tính lại bằng `polygonToCells`.
4. **Cách nạp `arenas`**: script seed (Node, dùng `h3-js` sẵn trong backend) đọc GeoJSON polygon, `INSERT ... ST_GeomFromGeoJSON`, rồi `polygonToCells(res 10)` để insert `h3_hexagons` và `UPDATE arenas SET total_hexes = <count>`. Nên đặt polygon trong file GeoJSON có version trong repo, không hard-code hình chữ nhật như `init_schema.sql`.

## Hiện trạng trong repo

- `backend/src/database/init_schema.sql` (mục 2): `arenas.boundary_polygon GEOMETRY(Polygon, 4326)` + GiST index `idx_arenas_boundary`; seed là **hình chữ nhật xấp xỉ** với `total_hexes` ghi tay (Sala 250, Landmark 81 180, Thanh Đa 120).
- `h3_hexagons.h3_index` là PRIMARY KEY và có `arena_id` FK: một ô chỉ thuộc **một** Đấu trường, nên các polygon không được chồng lấn.
- `backend/src/entities/arena.entity.ts`: **không map** `boundary_polygon` (chỉ id, name, description, total_hexes, is_active). Đọc/ghi polygon dùng raw SQL hoặc thêm cột `geometry` sau.
- `backend/src/modules/turf/h3.service.ts`: `MAX_HEX_PER_LOOP = 150` (ERR_301), res 10.

## Nguồn toạ độ (nguồn sơ cấp)

| Đấu trường | Đối tượng OSM | Loại | Ghi chú |
|---|---|---|---|
| Khu đô thị Sala | way 1424917259 | `landuse=residential`, polygon 106 đỉnh | Nominatim ghi địa chỉ Phường An Khánh, TP Thủ Đức (không thuộc Bình Thạnh dù seed gọi là "Bình Thạnh & lân cận") |
| Landmark 81 / Central Park | way 375888006 (`landuse`, Vinhomes Central Park) và way 504571792 (`leisure=park`, "Công viên Vinhomes Central Park") | polygon 54 / 82 đỉnh | Tòa Landmark 81 là điểm/building trong khu này; công viên ven sông là way 504571792 |
| Bờ kè Thanh Đa | way 1037121093 ("Công viên bờ sông Thanh Đa", `leisure=park`) | polygon 26 đỉnh, rất nhỏ | Không tìm thấy feature "bờ kè" nào trong OSM (Nominatim bounded search). Chỉ có các đường `Thanh Đa` (vd. way 32579703, 604529797). Cần tự vẽ polygon dọc bờ sông, ví dụ buffer vài chục mét quanh tuyến đường ven sông |

Cách lấy lại: `https://nominatim.openstreetmap.org/search?q=Khu do thi Sala&format=jsonv2&polygon_geojson=1` (cần header User-Agent), hoặc `https://api.openstreetmap.org/api/0.6/way/<id>/full.json`. Overpass API bị quá tải/502 khi điều tra, nên số liệu lấy qua OSM API v0.6 và Nominatim. Tên không dấu "Landmark 81" trên Nominatim trả về sai (khu PetroVietnam Landmark ở Bình Trưng), nên tra theo "Vinhomes Central Park" hoặc id way. Bên thứ ba (Google Maps...) không dùng vì điều khoản lưu trữ toạ độ; có thể tự vẽ trên geojson.io rồi review bằng mắt.

## Ước lượng số ô H3 res 10

Một ô res 10 có diện tích trung bình khoảng 15.048 m2, cạnh khoảng 75,9 m (`h3-js` 4.5.0: `getHexagonAreaAvg`, `getHexagonEdgeLengthAvg`). Đếm bằng `polygonToCells(ring, 10)` (ô có tâm nằm trong polygon), diện tích tính bằng shoelace trên toạ độ OSM:

| Vùng | Diện tích | Số ô | So với trần 150 |
|---|---|---|---|
| Sala (way 1424917259) | khoảng 875.000 m2 | **52** | thấp hơn |
| Vinhomes Central Park, toàn khu (way 375888006) | khoảng 407.500 m2 | **25** | thấp hơn |
| Công viên Vinhomes Central Park (way 504571792) | khoảng 148.500 m2 | **9** | thấp hơn |
| Công viên bờ sông Thanh Đa (way 1037121093) | khoảng 9.400 m2 | **1** | thấp hơn |
| Seed hiện tại, Sala (hình chữ nhật) | khoảng 0,9 x 1,0 km | 59 | `total_hexes` seed = 250 |
| Seed hiện tại, Landmark 81 | | 38 | seed = 180 |
| Seed hiện tại, Thanh Đa | | 56 | seed = 120 |

Ước lượng cho Bờ kè Thanh Đa (chưa có polygon, là ước tính): dải ven sông dài khoảng 2 đến 3 km, rộng 60 đến 100 m thì khoảng 10 đến 25 ô; muốn cả bán đảo Thanh Đa thì khoảng 150 đến 200 ô (vượt trần nếu claim một vòng). Hệ quả: **trần 150 ô không chặn việc nạp Đấu trường**, chỉ cần polygon Thanh Đa không phình quá lớn nếu muốn claim cả vùng trong một vòng. Ô H3 hẹp (cạnh khoảng 76 m) nên dải bờ kè rộng dưới 76 m có thể rơi ít ô; cân nhắc `polygonToCells` với polygon đã buffer, hoặc `gridPathCells` dọc tuyến.

## Vấn đề phát hiện thêm (ngoài phạm vi ticket, chưa sửa code)

1. `h3.service.ts` gọi `h3.polygonToCells(coordinates, 10, true)` với `coordinates` là `[lat, lng]` (từ `cellToLatLng`). Tham số thứ ba `true` nghĩa là GeoJSON `[lng, lat]`, nên lat/lng bị đảo. Cần kiểm tra/sửa (bỏ `true`, hoặc đảo thứ tự) trước khi dùng cho flood fill thật. Tài liệu: https://h3geo.org/docs/api/regions (`polygonToCells`, `isGeoJson`).
2. Hộp seed "Cụm Đại Học Bình Thạnh (Khu D2)" (lat 10.7980 đến 10.8065) chồng lấn nhẹ với hộp Landmark 81 (lat đến 10.7985); vì `h3_hexagons.h3_index` là PK, ô trùng chỉ gán được cho một Đấu trường.
3. Sala nằm ở An Khánh (Thủ Đức), không phải Bình Thạnh; nên chỉnh mô tả.

## Nguồn

- OSM Nominatim search API: https://nominatim.org/release-docs/latest/api/Search/ (truy vấn thực tế ngày 2026-11-04)
- OSM API v0.6 (way/full): https://wiki.openstreetmap.org/wiki/API_v0.6
- OSM way 1424917259, 375888006, 504571792, 1037121093 (https://www.openstreetmap.org/way/<id>)
- Giấy phép ODbL: https://www.openstreetmap.org/copyright
- H3 (độ phân giải, polygonToCells): https://h3geo.org/docs/core-library/restable và https://h3geo.org/docs/api/regions
- PostGIS `ST_GeomFromGeoJSON`, `ST_Contains`: https://postgis.net/docs/
- Mã nguồn repo: `backend/src/database/init_schema.sql`, `backend/src/entities/arena.entity.ts`, `backend/src/modules/turf/h3.service.ts`
