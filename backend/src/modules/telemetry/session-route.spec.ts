import { buildRoute, filterPlausiblePoints } from './session-route';

const p = (timestamp: number, lng = 106.7, lat = 10.8, accuracy = 5) => ({ lat, lng, timestamp, accuracy });

describe('buildRoute: vệt GPS của Phiên chạy thành MultiLineString', () => {
  it('nối điểm của các cửa sổ theo thời gian thành một đoạn, toạ độ [lng, lat]', () => {
    const route = buildRoute([
      { gps_points: [p(3000, 106.3), p(4000, 106.4)] },
      { gps_points: [p(1000, 106.1), p(2000, 106.2)] },
    ]);

    expect(route).toEqual({
      type: 'MultiLineString',
      coordinates: [[[106.1, 10.8], [106.2, 10.8], [106.3, 10.8], [106.4, 10.8]]],
    });
  });

  it('hai điểm cách nhau quá 15 s (Tạm dừng / mất tín hiệu) thì tách đoạn, không nối qua chỗ dừng', () => {
    const route = buildRoute([{ gps_points: [p(0, 1), p(1000, 2)] }, { gps_points: [p(17000, 3), p(18000, 4)] }]);

    expect(route.coordinates).toEqual([
      [[1, 10.8], [2, 10.8]],
      [[3, 10.8], [4, 10.8]],
    ]);
  });

  it('đúng 15 s vẫn cùng một đoạn', () => {
    expect(buildRoute([{ gps_points: [p(0), p(15000)] }]).coordinates).toHaveLength(1);
  });

  it('bỏ điểm chưa có tín hiệu (sai số âm) hoặc sai số > 20 m', () => {
    const route = buildRoute([{ gps_points: [p(0, 1), p(1000, 2, 10.8, -1), p(2000, 3, 10.8, 25), p(3000, 4)] }]);

    expect(route.coordinates).toEqual([[[1, 10.8], [4, 10.8]]]);
  });

  it('bỏ đoạn chỉ có một điểm (GeoJSON LineString cần ít nhất 2 điểm); không có điểm nào thì rỗng', () => {
    expect(buildRoute([{ gps_points: [p(0)] }, { gps_points: [] }]).coordinates).toEqual([]);
    expect(buildRoute([]).coordinates).toEqual([]);
  });
});

describe('filterPlausiblePoints: bỏ điểm GPS nhảy nhanh hơn sức người (> 9 m/s)', () => {
  // 1e-5 độ vĩ ≈ 1,11 m.
  const at = (timestamp: number, metersNorth: number, accuracy = 5) => ({
    lat: 10.8 + (metersNorth / 1.11) * 1e-5,
    lng: 106.7,
    timestamp,
    accuracy,
  });

  it('giữ điểm chạy bộ bình thường (3 m/s)', () => {
    const pts = [at(0, 0), at(1000, 3), at(2000, 6), at(3000, 9)];
    expect(filterPlausiblePoints(pts, null)).toEqual(pts);
  });

  it('bỏ một điểm nhảy 500 m trong 1 s (GPS nhiễu), giữ các điểm sau gần điểm trước đó', () => {
    const pts = [at(0, 0), at(1000, 500), at(2000, 6), at(3000, 9)];
    expect(filterPlausiblePoints(pts, null)).toEqual([at(0, 0), at(2000, 6), at(3000, 9)]);
  });

  it('dịch chuyển tức thời rồi chạy tiếp ở chỗ mới: bỏ hết tới khi thời gian đủ cho quãng đó', () => {
    const pts = [at(0, 0), at(1000, 2000), at(2000, 2003), at(300_000, 2010)];
    // 2010 m / 300 s = 6,7 m/s ≤ 9 m/s: điểm cuối hợp lý trở lại.
    expect(filterPlausiblePoints(pts, null)).toEqual([at(0, 0), at(300_000, 2010)]);
  });

  it('neo vào điểm cuối của Cửa sổ trước: điểm đầu Cửa sổ này cũng phải hợp lý', () => {
    const anchor = at(0, 0);
    expect(filterPlausiblePoints([at(1000, 800), at(2000, 4)], anchor)).toEqual([at(2000, 4)]);
  });

  it('bỏ điểm sai số âm hoặc > 20 m, không dùng chúng làm điểm neo', () => {
    const pts = [at(0, 0), at(1000, 300, 50), at(2000, 6, -1), at(3000, 9)];
    expect(filterPlausiblePoints(pts, null)).toEqual([at(0, 0), at(3000, 9)]);
  });

  it('sắp theo thời gian trước khi xét; trùng thời điểm mà khác chỗ thì bỏ', () => {
    expect(filterPlausiblePoints([at(2000, 6), at(0, 0), at(2000, 50)], null)).toEqual([at(0, 0), at(2000, 6)]);
  });
});
