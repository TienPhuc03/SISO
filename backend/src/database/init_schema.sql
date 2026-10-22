-- ============================================================================
-- SISO (STEP IN STEP OUT) — DATABASE SCHEMA & SEED DATA (POSTGRESQL 15 + POSTGIS)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 1. Bảng Trường Đại học
CREATE TABLE IF NOT EXISTS universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    short_code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    email_domain VARCHAR(50) UNIQUE NOT NULL,
    hex_color VARCHAR(7) NOT NULL,
    secondary_color VARCHAR(7),
    total_season_km FLOAT DEFAULT 0.0,
    logo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed 5 trường Đại học khu vực Bình Thạnh
INSERT INTO universities (short_code, name, email_domain, hex_color, secondary_color)
VALUES
    ('HUTECH', 'ĐH Công Nghệ TP.HCM (HUTECH)', 'hutech.edu.vn', '#FFCC00', '#003399'),
    ('UEF', 'ĐH Kinh Tế - Tài Chính TP.HCM (UEF)', 'uef.edu.vn', '#ED1C24', '#FFFFFF'),
    ('UTH', 'ĐH Giao Thông Vận Tải TP.HCM (UTH)', 'ut.edu.vn', '#002B49', '#FFFFFF'),
    ('FTU2', 'ĐH Ngoại Thương Cơ sở II (FTU2)', 'ftu.edu.vn', '#8A0000', '#FFFFFF'),
    ('HIU', 'ĐH Quốc Tế Hồng Bàng (HIU)', 'hiu.vn', '#D81B26', '#FFFFFF')
ON CONFLICT (email_domain) DO NOTHING;

-- 2. Bảng Danh mục Đấu trường Mở (Arenas)
CREATE TABLE IF NOT EXISTS arenas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    boundary_polygon GEOMETRY(Polygon, 4326),
    total_hexes INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed Đấu trường Bình Thạnh & Lân cận
INSERT INTO arenas (name, description, total_hexes)
VALUES
    ('Khu Đô Thị Sala', 'Cung đường chuẩn cao vỉa hè rộng 10m', 250),
    ('Công Viên Landmark 81', 'Quần thể công viên ven sông Central Park', 180),
    ('Khu Vực Bờ Kè Thanh Đa', 'Tuyến đường ven sông thoáng mát', 120)
ON CONFLICT DO NOTHING;

-- 3. Bảng Người dùng
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    university_id UUID REFERENCES universities(id),
    display_name VARCHAR(50),
    personal_km FLOAT DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Bảng Lãnh thổ Lục giác H3 (Resolution 10)
CREATE TABLE IF NOT EXISTS h3_hexagons (
    h3_index VARCHAR(15) PRIMARY KEY,
    arena_id UUID REFERENCES arenas(id),
    owner_university_id UUID REFERENCES universities(id),
    shield_hp INT DEFAULT 100,
    last_patrolled_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_h3_owner ON h3_hexagons(owner_university_id);
CREATE INDEX IF NOT EXISTS idx_h3_arena ON h3_hexagons(arena_id);

-- 5. Bảng Lịch sử Phiên Chạy
CREATE TABLE IF NOT EXISTS running_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_type VARCHAR(20) DEFAULT 'ARENA_LOOP',
    distance_meters FLOAT NOT NULL,
    duration_seconds INT NOT NULL,
    hex_count INT DEFAULT 0,
    is_valid BOOLEAN DEFAULT TRUE,
    rejection_reason VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. View tính Bộ đếm song song (% Đất & % Km Toàn Cầu)
CREATE OR REPLACE VIEW v_campus_live_scores AS
WITH territory_stats AS (
    SELECT 
        owner_university_id,
        COUNT(h3_index)::FLOAT AS owned_hexes
    FROM h3_hexagons
    WHERE owner_university_id IS NOT NULL
    GROUP BY owner_university_id
),
total_territory AS (
    SELECT COUNT(*)::FLOAT AS total_arena_hexes FROM h3_hexagons
),
mileage_stats AS (
    SELECT SUM(total_season_km)::FLOAT AS all_campus_km FROM universities
)
SELECT 
    u.id AS university_id,
    u.short_code,
    u.name,
    u.hex_color,
    u.total_season_km,
    COALESCE(ROUND((t.owned_hexes / NULLIF(tt.total_arena_hexes, 0) * 100)::NUMERIC, 2), 0.0) AS territory_pct,
    COALESCE(ROUND((u.total_season_km / NULLIF(m.all_campus_km, 0) * 100)::NUMERIC, 2), 0.0) AS mileage_pct,
    COALESCE(ROUND((
        0.5 * (COALESCE(t.owned_hexes / NULLIF(tt.total_arena_hexes, 0), 0)) +
        0.5 * (COALESCE(u.total_season_km / NULLIF(m.all_campus_km, 0), 0))
    ) * 100::NUMERIC, 2), 0.0) AS composite_power_pct
FROM universities u
CROSS JOIN total_territory tt
CROSS JOIN mileage_stats m
LEFT JOIN territory_stats t ON u.id = t.owner_university_id;
