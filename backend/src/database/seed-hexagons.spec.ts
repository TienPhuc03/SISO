import { cellToLatLng, getResolution, isValidCell } from 'h3-js';
import { ArenaFeature, buildSeedPlan, loadArenaFeatures } from './seed-hexagons';

const square = (name: string, lng0: number, lat0: number, size: number): ArenaFeature => ({
  type: 'Feature',
  properties: { name },
  geometry: {
    type: 'Polygon',
    coordinates: [
      [
        [lng0, lat0],
        [lng0 + size, lat0],
        [lng0 + size, lat0 + size],
        [lng0, lat0 + size],
        [lng0, lat0],
      ],
    ],
  },
});

describe('buildSeedPlan', () => {
  it('sinh ô H3 res 10 hợp lệ, nằm trong polygon [lng, lat]', () => {
    const [arena] = buildSeedPlan([square('A', 106.718, 10.791, 0.007)]);

    expect(arena.cells.length).toBeGreaterThan(10);
    for (const cell of arena.cells) {
      expect(isValidCell(cell)).toBe(true);
      expect(getResolution(cell)).toBe(10);
      const [lat, lng] = cellToLatLng(cell);
      expect(lat).toBeGreaterThanOrEqual(10.791);
      expect(lat).toBeLessThanOrEqual(10.798);
      expect(lng).toBeGreaterThanOrEqual(106.718);
      expect(lng).toBeLessThanOrEqual(106.725);
    }
  });

  it('ô trùng giữa hai polygon chỉ thuộc Đấu trường đứng trước', () => {
    const plan = buildSeedPlan([
      square('Trước', 106.718, 10.791, 0.007),
      square('Sau', 106.721, 10.791, 0.007), // chồng lấn nửa bên phải
    ]);

    const first = new Set(plan[0].cells);
    expect(plan[1].cells.some((c) => first.has(c))).toBe(false);
    expect(plan[1].overlapDropped).toBeGreaterThan(0);
    expect(plan[0].overlapDropped).toBe(0);
  });

  it('từ chối geometry không phải Polygon', () => {
    const bad = { ...square('X', 106.7, 10.8, 0.01), geometry: { type: 'Point', coordinates: [] } };
    expect(() => buildSeedPlan([bad as unknown as ArenaFeature])).toThrow('Polygon');
  });
});

describe('arenas.geojson trong repo', () => {
  const plan = buildSeedPlan(loadArenaFeatures());

  it('có 4 Đấu trường, mỗi cái có ô và dưới trần 150 ô/vòng claim', () => {
    expect(plan.map((a) => a.name)).toEqual([
      'Khu Đô Thị Sala',
      'Công Viên Landmark 81',
      'Khu Vực Bờ Kè Thanh Đa',
      'Cụm Đại Học Bình Thạnh (Khu D2)',
    ]);
    for (const a of plan) {
      expect(a.cells.length).toBeGreaterThan(0);
      expect(a.cells.length).toBeLessThanOrEqual(150);
    }
  });

  it('các ô nằm quanh khu Bình Thạnh (không đảo lat/lng)', () => {
    for (const cell of plan.flatMap((a) => a.cells)) {
      const [lat, lng] = cellToLatLng(cell);
      expect(lat).toBeGreaterThan(10.75);
      expect(lat).toBeLessThan(10.85);
      expect(lng).toBeGreaterThan(106.69);
      expect(lng).toBeLessThan(106.74);
    }
  });
});
