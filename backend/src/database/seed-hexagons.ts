/**
 * Nạp ranh giới Đấu trường từ `arenas.geojson` và sinh sẵn các ô H3 res 10 vào `h3_hexagons`.
 *
 *   npm run seed:hexagons              # dry-run: chỉ in số ô, KHÔNG ghi DB
 *   npm run seed:hexagons -- --apply   # ghi thật vào DB trong backend/.env (DATABASE_URL hoặc DB_*)
 *
 * Chạy lại nhiều lần vẫn an toàn:
 * - Đấu trường upsert theo `name` (cập nhật mô tả, polygon, total_hexes).
 * - Ô đã có thì giữ nguyên chủ sở hữu và HP; chỉ gán `arena_id` nếu ô đang chưa thuộc Đấu trường nào.
 * - Không xoá ô nào. Ô thuộc Đấu trường nhưng đã nằm ngoài polygon mới chỉ được báo lại.
 *
 * Nguồn và cách chọn ranh giới: docs/research/arena-boundaries.md (ticket #5).
 */
import { readFileSync } from 'fs';
import { join } from 'path';
import { polygonToCells } from 'h3-js';

export const SEED_RESOLUTION = 10;

export interface ArenaFeature {
  type: 'Feature';
  properties: { name: string; description?: string; source?: string };
  geometry: { type: 'Polygon'; coordinates: number[][][] };
}

export interface ArenaSeed {
  name: string;
  description: string | null;
  /** Polygon GeoJSON gốc, `[lng, lat]`. */
  geometry: ArenaFeature['geometry'];
  /** Ô thuộc Đấu trường này, đã loại các ô trùng với Đấu trường đứng trước. */
  cells: string[];
  /** Số ô bị bỏ vì đã thuộc Đấu trường đứng trước trong file (polygon chồng lấn). */
  overlapDropped: number;
}

/**
 * Tính tập ô cho từng Đấu trường. Một ô chỉ thuộc một Đấu trường (`h3_index` là khoá chính),
 * nên khi polygon chồng lấn, ô thuộc về Đấu trường xuất hiện trước trong file.
 */
export function buildSeedPlan(features: ArenaFeature[]): ArenaSeed[] {
  const taken = new Set<string>();
  return features.map((f) => {
    if (f.geometry?.type !== 'Polygon') {
      throw new Error(`Đấu trường "${f.properties?.name}" phải là Polygon`);
    }
    // isGeoJson = true vì toạ độ trong file là [lng, lat].
    const all = polygonToCells(f.geometry.coordinates, SEED_RESOLUTION, true);
    const cells = all.filter((c) => !taken.has(c));
    cells.forEach((c) => taken.add(c));
    return {
      name: f.properties.name,
      description: f.properties.description ?? null,
      geometry: f.geometry,
      cells,
      overlapDropped: all.length - cells.length,
    };
  });
}

export function loadArenaFeatures(path = join(__dirname, 'arenas.geojson')): ArenaFeature[] {
  const json = JSON.parse(readFileSync(path, 'utf8'));
  if (json?.type !== 'FeatureCollection' || !Array.isArray(json.features)) {
    throw new Error(`${path} không phải GeoJSON FeatureCollection`);
  }
  return json.features;
}

async function applyPlan(plan: ArenaSeed[]): Promise<void> {
  // Nạp lười để dry-run và unit test không cần cấu hình DB.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  require('dotenv').config({ path: join(__dirname, '..', '..', '.env') });
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { Client } = require('pg');

  const ssl = process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false;
  const client = process.env.DATABASE_URL
    ? new Client({ connectionString: process.env.DATABASE_URL, ssl })
    : new Client({
        host: process.env.DB_HOST,
        port: Number(process.env.DB_PORT ?? 5432),
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        ssl,
      });

  await client.connect();
  try {
    await client.query('BEGIN');
    for (const arena of plan) {
      const { rows } = await client.query(
        `INSERT INTO public.arenas (name, description, boundary_polygon, total_hexes)
         VALUES ($1, $2, ST_SetSRID(ST_GeomFromGeoJSON($3), 4326), $4)
         ON CONFLICT (name) DO UPDATE
           SET description = EXCLUDED.description,
               boundary_polygon = EXCLUDED.boundary_polygon
         RETURNING id`,
        [arena.name, arena.description, JSON.stringify(arena.geometry), arena.cells.length],
      );
      const arenaId: string = rows[0].id;

      const inserted = await client.query(
        `INSERT INTO public.h3_hexagons (h3_index, arena_id)
         SELECT unnest($1::text[]), $2
         ON CONFLICT (h3_index) DO UPDATE
           SET arena_id = EXCLUDED.arena_id
           WHERE public.h3_hexagons.arena_id IS NULL`,
        [arena.cells, arenaId],
      );

      const stale = await client.query(
        `SELECT COUNT(*)::int AS n FROM public.h3_hexagons
         WHERE arena_id = $1 AND NOT (h3_index = ANY($2::text[]))`,
        [arenaId, arena.cells],
      );

      // total_hexes = số ô thật đang gắn với Đấu trường trong DB.
      const total = await client.query(
        `UPDATE public.arenas
         SET total_hexes = (SELECT COUNT(*) FROM public.h3_hexagons WHERE arena_id = $1)
         WHERE id = $1
         RETURNING total_hexes`,
        [arenaId],
      );

      console.log(
        `  ✔ ${arena.name}: ghi mới/gán ${inserted.rowCount} ô, total_hexes = ${total.rows[0].total_hexes}` +
          (stale.rows[0].n ? `, ${stale.rows[0].n} ô cũ nằm ngoài polygon mới (không xoá)` : ''),
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    await client.end();
  }
}

async function main(): Promise<void> {
  const apply = process.argv.includes('--apply');
  const plan = buildSeedPlan(loadArenaFeatures());

  console.log(`Seed Đấu trường, H3 res ${SEED_RESOLUTION}${apply ? '' : ' (dry-run, không ghi DB)'}:`);
  for (const a of plan) {
    console.log(
      `  - ${a.name}: ${a.cells.length} ô` +
        (a.overlapDropped ? ` (bỏ ${a.overlapDropped} ô trùng Đấu trường trước)` : ''),
    );
  }
  console.log(`  Tổng: ${plan.reduce((s, a) => s + a.cells.length, 0)} ô`);

  if (!apply) {
    console.log('Thêm cờ --apply để ghi vào DB.');
    return;
  }
  await applyPlan(plan);
  console.log('Hoàn tất.');
}

if (require.main === module) {
  main().catch((e) => {
    console.error('Seed thất bại:', e.message ?? e);
    process.exit(1);
  });
}
