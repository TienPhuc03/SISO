-- ============================================================================
-- SISO (STEP IN STEP OUT) — PRODUCTION DATABASE SCHEMA & SEED DATA
-- Hỗ trợ: PostgreSQL 15 + PostGIS + pg_cron + Supabase Auth + RLS + Realtime
-- Thiết kế Idempotent (Non-destructive): Tương thích cả DB mới và DB nâng cấp
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Kích hoạt an toàn pg_cron (trên Supabase Cloud chạy tự động, trên Docker local bỏ qua nếu chưa cài)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS "pg_cron";
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron extension is not available in this environment, skipping.';
END $$;

-- ============================================================================
-- 1. BẢNG TRƯỜNG ĐẠI HỌC (UNIVERSITIES)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    short_code VARCHAR(20) UNIQUE NOT NULL,
    short_name VARCHAR(20),
    name VARCHAR(100) NOT NULL,
    email_domain VARCHAR(50) UNIQUE NOT NULL,
    hex_color VARCHAR(7) NOT NULL,
    secondary_color VARCHAR(7),
    total_season_km FLOAT DEFAULT 0.0,
    logo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Đồng bộ schema không phá hủy nếu bảng đã tồn tại từ phiên bản trước
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS short_code VARCHAR(20);
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS short_name VARCHAR(20);
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS secondary_color VARCHAR(7);
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS logo_url TEXT;

UPDATE public.universities SET short_code = short_name WHERE short_code IS NULL AND short_name IS NOT NULL;
UPDATE public.universities SET short_name = short_code WHERE short_name IS NULL AND short_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_universities_short_code ON public.universities(short_code);

-- Seed 5 trường Đại học khu vực Bình Thạnh (Chuẩn màu cờ sắc áo SRS Mục 1)
INSERT INTO public.universities (short_code, short_name, name, email_domain, hex_color, secondary_color)
VALUES
    ('HUTECH', 'HUTECH', 'ĐH Công Nghệ TP.HCM (HUTECH)', 'hutech.edu.vn', '#FFCC00', '#003399'),
    ('UEF', 'UEF', 'ĐH Kinh Tế - Tài Chính TP.HCM (UEF)', 'uef.edu.vn', '#ED1C24', '#FFFFFF'),
    ('UTH', 'UTH', 'ĐH Giao Thông Vận Tải TP.HCM (UTH)', 'ut.edu.vn', '#002B49', '#FFFFFF'),
    ('FTU2', 'FTU2', 'ĐH Ngoại Thương Cơ sở II (FTU2)', 'ftu.edu.vn', '#8A0000', '#FFFFFF'),
    ('HIU', 'HIU', 'ĐH Quốc Tế Hồng Bàng (HIU)', 'hiu.vn', '#D81B26', '#FFFFFF')
ON CONFLICT (email_domain) DO UPDATE
SET short_code = EXCLUDED.short_code,
    short_name = EXCLUDED.short_name,
    name = EXCLUDED.name,
    hex_color = EXCLUDED.hex_color,
    secondary_color = EXCLUDED.secondary_color;

-- ============================================================================
-- 2. BẢNG DANH MỤC ĐẤU TRƯỜNG MỞ (ARENAS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.arenas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    boundary_polygon GEOMETRY(Polygon, 4326),
    total_hexes INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.arenas ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.arenas ADD COLUMN IF NOT EXISTS boundary_polygon GEOMETRY(Polygon, 4326);
ALTER TABLE public.arenas ADD COLUMN IF NOT EXISTS total_hexes INT DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_arenas_name_unique ON public.arenas(name);
CREATE INDEX IF NOT EXISTS idx_arenas_boundary ON public.arenas USING GIST (boundary_polygon);

-- Seed Đấu trường Bình Thạnh & Lân cận (kèm đa giác ranh giới chuẩn PostGIS SRID 4326)
INSERT INTO public.arenas (name, description, boundary_polygon, total_hexes)
VALUES
    (
        'Khu Đô Thị Sala',
        'Cung đường chuẩn cao vỉa hè rộng 10m',
        ST_GeomFromText('POLYGON((106.7180 10.7680, 106.7270 10.7680, 106.7270 10.7770, 106.7180 10.7770, 106.7180 10.7680))', 4326),
        250
    ),
    (
        'Công Viên Landmark 81',
        'Quần thể công viên ven sông Central Park',
        ST_GeomFromText('POLYGON((106.7185 10.7910, 106.7255 10.7910, 106.7255 10.7985, 106.7185 10.7985, 106.7185 10.7910))', 4326),
        180
    ),
    (
        'Khu Vực Bờ Kè Thanh Đa',
        'Tuyến đường ven sông thoáng mát',
        ST_GeomFromText('POLYGON((106.7140 10.8070, 106.7230 10.8070, 106.7230 10.8160, 106.7140 10.8160, 106.7140 10.8070))', 4326),
        120
    ),
    (
        'Cụm Đại Học Bình Thạnh (Khu D2)',
        'Khuôn viên mở kết nối HUTECH - UEF - UTH - FTU2 - HIU',
        ST_GeomFromText('POLYGON((106.7105 10.7980, 106.7190 10.7980, 106.7190 10.8065, 106.7105 10.8065, 106.7105 10.7980))', 4326),
        160
    )
ON CONFLICT (name) DO UPDATE
SET boundary_polygon = EXCLUDED.boundary_polygon,
    description = EXCLUDED.description,
    total_hexes = EXCLUDED.total_hexes;

-- Cập nhật luôn cho bản ghi cũ 'Khu Vực Bình Thạnh & Landmark 81' nếu đã có sẵn
UPDATE public.arenas
SET description = COALESCE(description, 'Quần thể công viên ven sông Landmark 81 & Bình Thạnh'),
    boundary_polygon = COALESCE(
        boundary_polygon,
        ST_GeomFromText('POLYGON((106.7185 10.7910, 106.7255 10.7910, 106.7255 10.7985, 106.7185 10.7985, 106.7185 10.7910))', 4326)
    ),
    total_hexes = CASE WHEN total_hexes = 0 OR total_hexes IS NULL THEN 180 ELSE total_hexes END
WHERE name = 'Khu Vực Bình Thạnh & Landmark 81';

UPDATE public.arenas
SET description = COALESCE(description, 'Khu đô thị ven sông Vạn Phúc City'),
    boundary_polygon = COALESCE(
        boundary_polygon,
        ST_GeomFromText('POLYGON((106.7050 10.8350, 106.7160 10.8350, 106.7160 10.8450, 106.7050 10.8450, 106.7050 10.8350))', 4326)
    ),
    total_hexes = CASE WHEN total_hexes = 0 OR total_hexes IS NULL THEN 200 ELSE total_hexes END
WHERE name = 'Khu Đô Thị Vạn Phúc';

-- ============================================================================
-- 3. BẢNG NGƯỜI DÙNG (USERS - LIÊN KẾT VỚI AUTH)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    university_id UUID REFERENCES public.universities(id) ON DELETE SET NULL,
    display_name VARCHAR(50),
    personal_km FLOAT DEFAULT 0.0,
    trust_score FLOAT DEFAULT 100.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email VARCHAR(255);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS trust_score FLOAT DEFAULT 100.0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_university ON public.users(university_id);

-- ============================================================================
-- 4. BẢNG LÃNH THỔ LỤC GIÁC H3 (H3_HEXAGONS - RESOLUTION 10)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.h3_hexagons (
    h3_index VARCHAR(15) PRIMARY KEY,
    arena_id UUID REFERENCES public.arenas(id) ON DELETE CASCADE,
    owner_university_id UUID REFERENCES public.universities(id) ON DELETE SET NULL,
    last_captured_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    shield_hp INT DEFAULT 100 CHECK (shield_hp >= 0 AND shield_hp <= 100),
    last_patrolled_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.h3_hexagons ADD COLUMN IF NOT EXISTS last_captured_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.h3_hexagons ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_h3_index_btree ON public.h3_hexagons USING BTREE (h3_index);
CREATE INDEX IF NOT EXISTS idx_h3_owner ON public.h3_hexagons(owner_university_id);
CREATE INDEX IF NOT EXISTS idx_h3_arena ON public.h3_hexagons(arena_id);

-- ============================================================================
-- 5. BẢNG LỊCH SỬ PHIÊN CHẠY (RUNNING_SESSIONS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.running_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    arena_id UUID REFERENCES public.arenas(id) ON DELETE SET NULL,
    session_type VARCHAR(20) DEFAULT 'ARENA_LOOP',
    distance_meters FLOAT NOT NULL CHECK (distance_meters >= 0),
    duration_seconds INT NOT NULL CHECK (duration_seconds > 0),
    hex_count INT DEFAULT 0,
    is_valid BOOLEAN DEFAULT TRUE,
    rejection_reason VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS arena_id UUID REFERENCES public.arenas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_user ON public.running_sessions(user_id);

-- ============================================================================
-- 6. BẢNG NHẬT KÝ CHẶN DỮ LIỆU RÁC (GIGO_AUDIT_LOGS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.gigo_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.running_sessions(id) ON DELETE SET NULL,
    rejection_type VARCHAR(50) NOT NULL,
    raw_gps_speed_mps FLOAT NOT NULL,
    imu_cadence_spm INT NOT NULL,
    vertical_energy_g FLOAT,
    gps_accuracy_m FLOAT,
    detected_at_h3 VARCHAR(15),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES public.running_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS rejection_type VARCHAR(50);
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS raw_gps_speed_mps FLOAT DEFAULT 0.0;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS imu_cadence_spm INT DEFAULT 0;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS vertical_energy_g FLOAT;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS gps_accuracy_m FLOAT;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS detected_at_h3 VARCHAR(15);

CREATE INDEX IF NOT EXISTS idx_gigo_user ON public.gigo_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_gigo_type ON public.gigo_audit_logs(rejection_type);

-- ============================================================================
-- 6B. BẢNG MÙA GIẢI 30 NGÀY (SEASONS) & ĐẠI SẢNH DANH VỌNG (HALL_OF_FAME)
-- Khớp 100% với ERD Mục 10 của SRS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.seasons (
    season_number INT PRIMARY KEY,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO public.seasons (season_number, start_date, end_date, is_active)
VALUES (1, '2026-10-01', '2026-10-31', TRUE)
ON CONFLICT (season_number) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.hall_of_fame (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    season_number INT REFERENCES public.seasons(season_number) ON DELETE CASCADE,
    champion_university_id UUID REFERENCES public.universities(id) ON DELETE CASCADE,
    territory_pct FLOAT DEFAULT 0.0,
    mileage_pct FLOAT DEFAULT 0.0,
    composite_power_pct FLOAT DEFAULT 0.0,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hof_season ON public.hall_of_fame(season_number);
CREATE INDEX IF NOT EXISTS idx_hof_champion ON public.hall_of_fame(champion_university_id);

-- ============================================================================
-- 7. VIEW TÍNH BỘ ĐẾM SONG SONG (% ĐẤT & % KM TOÀN CẦU)
-- Giữ nguyên thứ tự cột cũ và bổ sung cột short_code ở cuối để không cần DROP VIEW
-- ============================================================================
CREATE OR REPLACE VIEW public.v_campus_live_scores
WITH (security_invoker = true)
AS
WITH territory_stats AS (
    SELECT 
        owner_university_id,
        COUNT(h3_index)::FLOAT AS owned_hexes
    FROM public.h3_hexagons
    WHERE owner_university_id IS NOT NULL
    GROUP BY owner_university_id
),
total_territory AS (
    SELECT COUNT(*)::FLOAT AS total_arena_hexes FROM public.h3_hexagons
),
mileage_stats AS (
    SELECT SUM(total_season_km)::FLOAT AS all_campus_km FROM public.universities
)
SELECT 
    u.id AS university_id,
    u.name,
    COALESCE(u.short_name, u.short_code) AS short_name,
    u.hex_color,
    u.total_season_km,
    COALESCE(ROUND((t.owned_hexes / NULLIF(tt.total_arena_hexes, 0) * 100)::NUMERIC, 2), 0.0) AS territory_pct,
    COALESCE(ROUND((u.total_season_km / NULLIF(m.all_campus_km, 0) * 100)::NUMERIC, 2), 0.0) AS mileage_pct,
    COALESCE(ROUND(((
        0.5 * COALESCE(t.owned_hexes / NULLIF(tt.total_arena_hexes, 0), 0) +
        0.5 * COALESCE(u.total_season_km / NULLIF(m.all_campus_km, 0), 0)
    ) * 100)::NUMERIC, 2), 0.0) AS composite_power_pct,
    u.short_code
FROM public.universities u
CROSS JOIN total_territory tt
CROSS JOIN mileage_stats m
LEFT JOIN territory_stats t ON u.id = t.owner_university_id;

-- ============================================================================
-- 8. TRIGGER TỰ ĐỘNG GÁN TRƯỜNG ĐẠI HỌC KHI ĐĂNG KÝ EMAIL @EDU.VN
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_student_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_domain VARCHAR(50);
    v_uni_id UUID;
BEGIN
    v_domain := split_part(NEW.email, '@', 2);

    SELECT id INTO v_uni_id
    FROM public.universities
    WHERE v_domain = email_domain OR v_domain LIKE '%.' || email_domain
    LIMIT 1;

    INSERT INTO public.users (id, email, university_id, display_name)
    VALUES (
        NEW.id,
        NEW.email,
        v_uni_id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        university_id = COALESCE(public.users.university_id, EXCLUDED.university_id);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_student_user();

-- ============================================================================
-- 9. CẤU HÌNH ROW LEVEL SECURITY (RLS) CHUẨN BẢO MẬT SUPABASE
-- ============================================================================
ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arenas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.h3_hexagons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.running_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gigo_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hall_of_fame ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read universities" ON public.universities;
CREATE POLICY "Public read universities" ON public.universities FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read arenas" ON public.arenas;
CREATE POLICY "Public read arenas" ON public.arenas FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read h3_hexagons" ON public.h3_hexagons;
CREATE POLICY "Public read h3_hexagons" ON public.h3_hexagons FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read users leaderboard" ON public.users;
CREATE POLICY "Public read users leaderboard" ON public.users FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read seasons" ON public.seasons;
CREATE POLICY "Public read seasons" ON public.seasons FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read hall_of_fame" ON public.hall_of_fame;
CREATE POLICY "Public read hall_of_fame" ON public.hall_of_fame FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users update own profile" ON public.users;
CREATE POLICY "Users update own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users read own sessions" ON public.running_sessions;
CREATE POLICY "Users read own sessions" ON public.running_sessions
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own sessions" ON public.running_sessions;
CREATE POLICY "Users insert own sessions" ON public.running_sessions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Public read gigo logs for stats" ON public.gigo_audit_logs;
CREATE POLICY "Public read gigo logs for stats" ON public.gigo_audit_logs
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users insert own gigo logs" ON public.gigo_audit_logs;
CREATE POLICY "Users insert own gigo logs" ON public.gigo_audit_logs
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- 10. BẬT SUPABASE REALTIME CHO BẢN ĐỒ LỤC GIÁC & ĐIỂM SỐ TRƯỜNG
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'h3_hexagons'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.h3_hexagons;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'universities'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.universities;
    END IF;
END $$;
