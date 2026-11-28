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
-- Ranh giới ở đây là hình chữ nhật xấp xỉ, total_hexes ghi tay. Ranh giới chuẩn (OSM) và các ô H3 nạp bằng
-- `npm run seed:hexagons -- --apply` (đọc src/database/arenas.geojson, tính lại total_hexes theo số ô thật).
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

-- [Hồ sơ] Ảnh đại diện tách bảng riêng: bảng users cho đọc công khai, ảnh thì chỉ backend đọc.
CREATE TABLE IF NOT EXISTS public.user_avatars (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    image BYTEA NOT NULL CHECK (octet_length(image) <= 524288),   -- 512 KB, khớp MAX_AVATAR_BYTES
    mime_type VARCHAR(20) NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

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

-- h3_index đã là PRIMARY KEY nên Postgres tự có B-Tree index; không cần index riêng.
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
    distance_meters FLOAT NOT NULL DEFAULT 0 CHECK (distance_meters >= 0),
    duration_seconds INT NOT NULL DEFAULT 0 CONSTRAINT running_sessions_duration_nonnegative CHECK (duration_seconds >= 0),
    hex_count INT DEFAULT 0,
    is_valid BOOLEAN DEFAULT TRUE,
    rejection_reason VARCHAR(50),
    -- [Module 4] Phiên chạy được kiểm định theo từng cửa sổ 256 mẫu (ACTIVE -> REJECTED | COMPLETED)
    status VARCHAR(20) NOT NULL DEFAULT 'COMPLETED'
        CONSTRAINT running_sessions_status_check CHECK (status IN ('ACTIVE', 'REJECTED', 'COMPLETED')),
    consecutive_biometric_failures INT NOT NULL DEFAULT 0,
    last_window_seq INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS arena_id UUID REFERENCES public.arenas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_user ON public.running_sessions(user_id);

-- [Module 4] Nâng cấp bảng cũ: thêm trạng thái Phiên chạy và bộ đếm cửa sổ không qua Cổng Sinh trắc.
-- Mặc định 'COMPLETED' để các dòng cũ (và claim-loop hiện tại, chưa gửi status) không bị coi là đang chạy.
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'COMPLETED';
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS consecutive_biometric_failures INT NOT NULL DEFAULT 0;
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS last_window_seq INT NOT NULL DEFAULT 0;
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.running_sessions ALTER COLUMN distance_meters SET DEFAULT 0;
ALTER TABLE public.running_sessions ALTER COLUMN duration_seconds SET DEFAULT 0;

-- Phiên chạy được tạo ở cửa sổ đầu tiên với thời lượng 0, nên bỏ ràng buộc cũ duration_seconds > 0.
DO $$
DECLARE
    old_check TEXT;
BEGIN
    FOR old_check IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.running_sessions'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%duration_seconds > 0%'
    LOOP
        EXECUTE format('ALTER TABLE public.running_sessions DROP CONSTRAINT %I', old_check);
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.running_sessions'::regclass
          AND conname = 'running_sessions_duration_nonnegative'
    ) THEN
        ALTER TABLE public.running_sessions
            ADD CONSTRAINT running_sessions_duration_nonnegative CHECK (duration_seconds >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.running_sessions'::regclass
          AND conname = 'running_sessions_status_check'
    ) THEN
        ALTER TABLE public.running_sessions
            ADD CONSTRAINT running_sessions_status_check CHECK (status IN ('ACTIVE', 'REJECTED', 'COMPLETED'));
    END IF;
END $$;

-- [Đường chạy] Thời điểm Phiên chạy kết thúc (COMPLETED hoặc REJECTED); NULL khi còn ACTIVE.
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS finished_at TIMESTAMP WITH TIME ZONE;

-- ============================================================================
-- 5b. BẢNG CỬA SỔ CỦA PHIÊN CHẠY (SESSION_WINDOWS)
-- Mỗi cửa sổ 5,12 s đã qua Cổng Động học là một dòng: vệt GPS + tốc độ/nhịp bước cho Lịch sử Phiên chạy.
-- Vệt lưu JSONB vì không có truy vấn không gian nào; đối chiếu ô H3 làm bằng h3-js ở backend.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.session_windows (
    session_id UUID NOT NULL REFERENCES public.running_sessions(id) ON DELETE CASCADE,
    seq INT NOT NULL CHECK (seq >= 0),                -- cửa sổ đầu = 0
    speed_mps FLOAT NOT NULL CHECK (speed_mps >= 0),
    cadence_spm INT NOT NULL DEFAULT 0,
    passed BOOLEAN NOT NULL,                           -- false = cửa sổ chỉ bị cảnh báo ở Cổng Sinh trắc
    gps_points JSONB NOT NULL DEFAULT '[]'::jsonb,     -- [{lat, lng, timestamp, accuracy}]
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL,     -- thời điểm mẫu IMU đầu tiên của cửa sổ
    PRIMARY KEY (session_id, seq)
);

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
-- Cột của schema cũ còn sót trên DB đã có: violation_type NOT NULL làm mọi lần ghi nhật ký khi loại Phiên lỗi.
ALTER TABLE public.gigo_audit_logs
    DROP COLUMN IF EXISTS violation_type,
    DROP COLUMN IF EXISTS gps_speed_mps,
    DROP COLUMN IF EXISTS cadence_spm,
    DROP COLUMN IF EXISTS fft_peak_freq;

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
-- 6C. CỤM (CLUSTERS), QUẬN (DISTRICTS) & TRƯỜNG THEO CƠ SỞ
-- Mỗi dòng universities là một cơ sở thi đấu (vd. "UEH – Cơ sở N"), thuộc đúng một Cụm qua quận.
-- Bảng xếp hạng, % Lãnh thổ, % Km và Quán quân tính riêng trong từng Cụm.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.clusters (
    code VARCHAR(20) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0
);

INSERT INTO public.clusters (code, name, sort_order) VALUES
    ('THU_DUC', 'Cụm Khu đô thị ĐHQG (TP. Thủ Đức - Khu Đông)', 1),
    ('CENTRAL', 'Cụm Trung tâm (Quận 1, 3, 5, 10)', 2),
    ('NORTH', 'Cụm Bình Thạnh - Phú Nhuận - Gò Vấp (Khu Bắc & Đông Bắc)', 3),
    ('SOUTH', 'Cụm Khu Nam (Quận 7, Bình Chánh)', 4)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order;

-- Quận cũ (trước 7/2025) -> Cụm. Quận ngoài 4 Cụm gốc được gán vào Cụm gần nhất.
-- Sửa ánh xạ ở đây rồi chạy lại khối này: mọi Trường của quận đó đổi Cụm theo.
CREATE TABLE IF NOT EXISTS public.districts (
    name VARCHAR(60) PRIMARY KEY,
    cluster_code VARCHAR(20) NOT NULL REFERENCES public.clusters(code),
    sort_order INT NOT NULL DEFAULT 0
);

INSERT INTO public.districts (name, cluster_code, sort_order) VALUES
    ('TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'THU_DUC', 1),
    ('Dĩ An (KĐT ĐHQG, Bình Dương cũ)', 'THU_DUC', 2),
    ('Quận 1', 'CENTRAL', 10),
    ('Quận 3', 'CENTRAL', 11),
    ('Quận 5', 'CENTRAL', 12),
    ('Quận 10', 'CENTRAL', 13),
    ('Quận 6', 'CENTRAL', 14),
    ('Quận 11', 'CENTRAL', 15),
    ('Tân Phú', 'CENTRAL', 16),
    ('Bình Tân', 'CENTRAL', 17),
    ('Bình Thạnh', 'NORTH', 20),
    ('Phú Nhuận', 'NORTH', 21),
    ('Gò Vấp', 'NORTH', 22),
    ('Tân Bình', 'NORTH', 23),
    ('Quận 12', 'NORTH', 24),
    ('Hóc Môn', 'NORTH', 25),
    ('Củ Chi', 'NORTH', 26),
    ('Quận 7', 'SOUTH', 30),
    ('Bình Chánh', 'SOUTH', 31),
    ('Quận 4', 'SOUTH', 32),
    ('Quận 8', 'SOUTH', 33),
    ('Nhà Bè', 'SOUTH', 34),
    ('Cần Giờ', 'SOUTH', 35)
ON CONFLICT (name) DO UPDATE SET cluster_code = EXCLUDED.cluster_code, sort_order = EXCLUDED.sort_order;

ALTER TABLE public.universities ALTER COLUMN email_domain DROP NOT NULL;
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS district VARCHAR(60) REFERENCES public.districts(name) ON UPDATE CASCADE;
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS parent_name VARCHAR(60);   -- thương hiệu chung của các cơ sở (vd. UEH)
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS aliases TEXT;              -- từ khoá tìm thêm, không dấu
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT TRUE; -- FALSE = Sinh viên tự thêm, chờ admin duyệt
ALTER TABLE public.universities ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

-- Mùa giải lúc Sinh viên chọn Trường gần nhất; NULL = chọn trước khi có luật khoá theo Mùa.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS university_season INT;

-- Đấu trường thuộc đúng một Cụm; chỉ Sinh viên của Cụm đó Chiếm / Tuần tra / Công phá được.
ALTER TABLE public.arenas ADD COLUMN IF NOT EXISTS cluster_code VARCHAR(20) NOT NULL DEFAULT 'NORTH' REFERENCES public.clusters(code);

-- Mỗi Cụm một Quán quân mỗi Mùa; các Mùa cũ đều là Bình Thạnh.
ALTER TABLE public.hall_of_fame ADD COLUMN IF NOT EXISTS cluster_code VARCHAR(20) REFERENCES public.clusters(code);
UPDATE public.hall_of_fame SET cluster_code = 'NORTH' WHERE cluster_code IS NULL;

-- 5 trường MVP: cơ sở Bình Thạnh.
UPDATE public.universities SET district = 'Bình Thạnh', parent_name = short_code
WHERE short_code IN ('HUTECH', 'UEF', 'UTH', 'FTU2', 'HIU') AND district IS NULL;
UPDATE public.universities SET aliases = v.aliases
FROM (VALUES
    ('HUTECH', 'cong nghe tphcm hutech'),
    ('UEF', 'kinh te tai chinh uef'),
    ('UTH', 'giao thong van tai uth ut'),
    ('FTU2', 'ngoai thuong ftu'),
    ('HIU', 'quoc te hong bang hiu')
) AS v(code, aliases)
WHERE short_code = v.code AND universities.aliases IS NULL;

-- Danh sách gốc các cơ sở nổi bật của 4 Cụm (Sinh viên chọn được ngay; trường khác tự thêm trong app).
INSERT INTO public.universities (short_code, short_name, name, parent_name, district, aliases, hex_color)
VALUES
    -- Cụm Thủ Đức
    ('HCMUT-DA', 'HCMUT Dĩ An', 'ĐH Bách khoa - ĐHQG TP.HCM (Cơ sở Dĩ An)', 'HCMUT', 'Dĩ An (KĐT ĐHQG, Bình Dương cũ)', 'bach khoa bk dhqg', '#0E4C92'),
    ('HCMUS-LT', 'HCMUS Linh Trung', 'ĐH Khoa học Tự nhiên - ĐHQG TP.HCM (Cơ sở Linh Trung)', 'HCMUS', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'khoa hoc tu nhien khtn dhqg', '#1565C0'),
    ('USSH-TD', 'USSH Thủ Đức', 'ĐH Khoa học Xã hội và Nhân văn - ĐHQG TP.HCM (Cơ sở Thủ Đức)', 'USSH', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'xa hoi nhan van khxhnv nhan van dhqg', '#B71C1C'),
    ('IU', 'IU', 'ĐH Quốc tế - ĐHQG TP.HCM', 'IU', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'quoc te hcmiu dhqg', '#1A237E'),
    ('UIT', 'UIT', 'ĐH Công nghệ Thông tin - ĐHQG TP.HCM', 'UIT', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'cong nghe thong tin cntt dhqg', '#0277BD'),
    ('UEL', 'UEL', 'ĐH Kinh tế - Luật - ĐHQG TP.HCM', 'UEL', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'kinh te luat dhqg', '#00695C'),
    ('HCMUTE', 'HCMUTE', 'ĐH Sư phạm Kỹ thuật TP.HCM', 'HCMUTE', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'su pham ky thuat spkt ute', '#0D47A1'),
    ('NLU', 'NLU', 'ĐH Nông Lâm TP.HCM', 'NLU', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'nong lam hcmuaf', '#2E7D32'),
    ('HUB-TD', 'HUB Thủ Đức', 'ĐH Ngân hàng TP.HCM (Cơ sở Thủ Đức)', 'HUB', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'ngan hang buh', '#004B8D'),
    ('ULAW-TD', 'ULAW Thủ Đức', 'ĐH Luật TP.HCM (Cơ sở Thủ Đức)', 'ULAW', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'luat hcmulaw', '#8D1B1B'),
    ('HUTECH-TD', 'HUTECH Thủ Đức', 'ĐH Công nghệ TP.HCM (HUTECH) - Cơ sở Khu Công nghệ cao', 'HUTECH', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'cong nghe tphcm hutech khu cong nghe cao', '#FFCC00'),
    ('FPTU', 'FPTU', 'ĐH FPT TP.HCM', 'FPTU', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'fpt', '#F37021'),
    ('UTC2', 'UTC2', 'ĐH Giao thông Vận tải - Phân hiệu TP.HCM', 'UTC', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'giao thong van tai gtvt utc', '#1E3A8A'),
    ('PTIT-HCM', 'PTIT HCM', 'Học viện Công nghệ Bưu chính Viễn thông - Cơ sở TP.HCM', 'PTIT', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'buu chinh vien thong ptit ptithcm hoc vien', '#C8102E'),
    ('SIU', 'SIU', 'ĐH Quốc tế Sài Gòn (SIU)', 'SIU', 'TP. Thủ Đức (Q2, Q9, Thủ Đức cũ)', 'quoc te sai gon siu', '#00539B'),
    -- Cụm Trung tâm
    ('HCMUT-LTK', 'HCMUT Q10', 'ĐH Bách khoa - ĐHQG TP.HCM (Cơ sở Lý Thường Kiệt)', 'HCMUT', 'Quận 10', 'bach khoa bk dhqg ly thuong kiet', '#0E4C92'),
    ('HCMUS-NVC', 'HCMUS Q5', 'ĐH Khoa học Tự nhiên - ĐHQG TP.HCM (Cơ sở Nguyễn Văn Cừ)', 'HCMUS', 'Quận 5', 'khoa hoc tu nhien khtn dhqg nguyen van cu', '#1565C0'),
    ('USSH-DTH', 'USSH Q1', 'ĐH Khoa học Xã hội và Nhân văn - ĐHQG TP.HCM (Cơ sở Đinh Tiên Hoàng)', 'USSH', 'Quận 1', 'xa hoi nhan van khxhnv nhan van dhqg', '#B71C1C'),
    ('UEH-A', 'UEH Cơ sở A', 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở A (Nguyễn Đình Chiểu)', 'UEH', 'Quận 3', 'kinh te ueh', '#005F69'),
    ('UEH-B', 'UEH Cơ sở B', 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở B (Nguyễn Tri Phương)', 'UEH', 'Quận 10', 'kinh te ueh', '#005F69'),
    ('HCMUE', 'HCMUE', 'ĐH Sư phạm TP.HCM', 'HCMUE', 'Quận 5', 'su pham dhsp', '#1F4E9E'),
    ('SGU', 'SGU', 'ĐH Sài Gòn', 'SGU', 'Quận 5', 'sai gon', '#0B6E4F'),
    ('UMP', 'UMP', 'ĐH Y Dược TP.HCM', 'UMP', 'Quận 5', 'y duoc yds', '#00838F'),
    ('UAH', 'UAH', 'ĐH Kiến trúc TP.HCM', 'UAH', 'Quận 3', 'kien truc', '#5D4037'),
    ('OU', 'OU', 'ĐH Mở TP.HCM', 'OU', 'Quận 3', 'mo ou', '#1E40AF'),
    ('HUB-Q1', 'HUB Q1', 'ĐH Ngân hàng TP.HCM (Cơ sở Tôn Thất Đạm)', 'HUB', 'Quận 1', 'ngan hang buh', '#004B8D'),
    ('HSU', 'HSU', 'ĐH Hoa Sen', 'HSU', 'Quận 1', 'hoa sen', '#E65100'),
    ('PNTU', 'PNTU', 'ĐH Y khoa Phạm Ngọc Thạch', 'PNTU', 'Quận 10', 'y khoa pham ngoc thach', '#00796B'),
    ('HUFI', 'HUFI', 'ĐH Công Thương TP.HCM (HUFI)', 'HUFI', 'Tân Phú', 'cong thuong cong nghiep thuc pham', '#C62828'),
    ('HUFLIT', 'HUFLIT', 'ĐH Ngoại ngữ - Tin học TP.HCM (HUFLIT)', 'HUFLIT', 'Quận 10', 'ngoai ngu tin hoc huflit', '#D4145A'),
    ('VHU', 'VHU', 'ĐH Văn Hiến', 'VHU', 'Tân Phú', 'van hien vhu', '#F7941D'),
    ('UPES', 'UPES', 'ĐH Sư phạm Thể dục Thể thao TP.HCM', 'UPES', 'Quận 5', 'su pham the duc the thao tdtt upes', '#2E7D32'),
    -- Cụm Bình Thạnh - Phú Nhuận - Gò Vấp
    ('IUH', 'IUH', 'ĐH Công nghiệp TP.HCM', 'IUH', 'Gò Vấp', 'cong nghiep', '#1565C0'),
    ('VLU', 'VLU', 'ĐH Văn Lang (Cơ sở chính Bình Thạnh)', 'VLU', 'Bình Thạnh', 'van lang', '#D71920'),
    ('HCMUFA', 'HCMUFA', 'ĐH Mỹ thuật TP.HCM', 'HCMUFA', 'Bình Thạnh', 'my thuat', '#6A1B9A'),
    ('GDU', 'GDU', 'ĐH Gia Định', 'GDU', 'Gò Vấp', 'gia dinh', '#283593'),
    ('UFM', 'UFM', 'ĐH Tài chính - Marketing', 'UFM', 'Phú Nhuận', 'tai chinh marketing', '#0D47A1'),
    ('VAA', 'VAA', 'Học viện Hàng không Việt Nam', 'VAA', 'Phú Nhuận', 'hang khong', '#0277BD'),
    ('NTTU-Q12', 'NTTU Q12', 'ĐH Nguyễn Tất Thành (Cơ sở An Phú Đông)', 'NTTU', 'Quận 12', 'nguyen tat thanh ntt', '#0057A8'),
    ('ULSA2', 'ULSA CS2', 'ĐH Lao động - Xã hội (Cơ sở II TP.HCM)', 'ULSA', 'Quận 12', 'lao dong xa hoi ldxh ulsa', '#1B5E20'),
    -- Cụm Khu Nam
    ('TDTU', 'TDTU', 'ĐH Tôn Đức Thắng', 'TDTU', 'Quận 7', 'ton duc thang', '#1A4F9C'),
    ('RMIT', 'RMIT', 'ĐH RMIT Việt Nam (Nam Sài Gòn)', 'RMIT', 'Quận 7', 'rmit', '#E60028'),
    ('UEH-N', 'UEH Cơ sở N', 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở N (Bình Chánh)', 'UEH', 'Bình Chánh', 'kinh te ueh', '#005F69'),
    ('ULAW-Q4', 'ULAW Q4', 'ĐH Luật TP.HCM (Cơ sở Nguyễn Tất Thành)', 'ULAW', 'Quận 4', 'luat hcmulaw', '#8D1B1B'),
    ('NTTU-Q4', 'NTTU Q4', 'ĐH Nguyễn Tất Thành (Cơ sở Quận 4)', 'NTTU', 'Quận 4', 'nguyen tat thanh ntt', '#0057A8'),
    ('STU', 'STU', 'ĐH Công nghệ Sài Gòn', 'STU', 'Quận 8', 'cong nghe sai gon', '#00897B')
ON CONFLICT (short_code) DO UPDATE
SET short_name = EXCLUDED.short_name,
    name = EXCLUDED.name,
    parent_name = EXCLUDED.parent_name,
    district = EXCLUDED.district,
    aliases = EXCLUDED.aliases;

-- Tên trường không trùng nhau (không phân biệt hoa thường) để Sinh viên tự thêm không tạo trùng.
CREATE UNIQUE INDEX IF NOT EXISTS uq_universities_name_ci ON public.universities (lower(name));

DROP POLICY IF EXISTS "Public read clusters" ON public.clusters;
ALTER TABLE public.clusters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read clusters" ON public.clusters FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public read districts" ON public.districts;
ALTER TABLE public.districts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read districts" ON public.districts FOR SELECT USING (true);

-- ============================================================================
-- 7. VIEW TÍNH BỘ ĐẾM SONG SONG (% ĐẤT & % KM) THEO CỤM
-- % Lãnh thổ: Ô đất của Trường trong các Đấu trường đang hoạt động của Cụm / tổng Ô đất các Đấu trường đó.
-- % Km: Quỹ Km của Trường / tổng Quỹ Km các Trường cùng Cụm.
-- Cụm chưa có Đấu trường: Sức mạnh Tổng hợp = 100% theo % Km.
-- Giữ nguyên thứ tự cột cũ, cột mới thêm ở cuối để không cần DROP VIEW.
-- ============================================================================
CREATE OR REPLACE VIEW public.v_campus_live_scores
WITH (security_invoker = true)
AS
WITH uni AS (
    SELECT u.*, d.cluster_code
    FROM public.universities u
    LEFT JOIN public.districts d ON d.name = u.district
),
hex AS (
    -- shortcut: Ô đất không gắn Đấu trường (chiếm trong khu thi đấu Bình Thạnh, không gửi arenaId) tính vào Cụm NORTH;
    -- bỏ khi mọi Vòng khép đều gửi arenaId.
    SELECT h.owner_university_id, COALESCE(a.cluster_code, 'NORTH') AS cluster_code
    FROM public.h3_hexagons h
    LEFT JOIN public.arenas a ON a.id = h.arena_id
    WHERE a.id IS NULL OR a.is_active
),
cluster_hexes AS (
    SELECT cluster_code, COUNT(*)::FLOAT AS total_hexes FROM hex GROUP BY cluster_code
),
owned AS (
    SELECT owner_university_id, cluster_code, COUNT(*)::FLOAT AS owned_hexes
    FROM hex WHERE owner_university_id IS NOT NULL
    GROUP BY owner_university_id, cluster_code
),
cluster_km AS (
    SELECT cluster_code, SUM(total_season_km)::FLOAT AS cluster_km FROM uni GROUP BY cluster_code
),
pct AS (
    SELECT u.*,
           COALESCE(o.owned_hexes / NULLIF(ch.total_hexes, 0), 0) AS t,
           COALESCE(u.total_season_km / NULLIF(ck.cluster_km, 0), 0) AS m,
           COALESCE(ch.total_hexes, 0) > 0 AS has_arena
    FROM uni u
    LEFT JOIN owned o ON o.owner_university_id = u.id AND o.cluster_code = u.cluster_code
    LEFT JOIN cluster_hexes ch ON ch.cluster_code = u.cluster_code
    LEFT JOIN cluster_km ck ON ck.cluster_code = u.cluster_code
)
SELECT
    p.id AS university_id,
    p.name,
    COALESCE(p.short_name, p.short_code) AS short_name,
    p.hex_color,
    p.total_season_km,
    COALESCE(ROUND((p.t * 100)::NUMERIC, 2), 0.0) AS territory_pct,
    COALESCE(ROUND((p.m * 100)::NUMERIC, 2), 0.0) AS mileage_pct,
    COALESCE(ROUND(((CASE WHEN p.has_arena THEN 0.5 * p.t + 0.5 * p.m ELSE p.m END) * 100)::NUMERIC, 2), 0.0)
        AS composite_power_pct,
    p.short_code,
    p.cluster_code,
    p.has_arena AS cluster_has_arena
FROM pct p;

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

-- Đăng ký bằng email bất kỳ (OTP hoặc Google); Sinh viên tự chọn Trường trong app.
-- Bỏ trigger cũ ép university_id theo đuôi email (trước đây chặn email ngoài 5 trường).
DROP TRIGGER IF EXISTS before_insert_user ON public.users;
DROP FUNCTION IF EXISTS public.assign_university_id();

-- ============================================================================
-- 9. CẤU HÌNH ROW LEVEL SECURITY (RLS) CHUẨN BẢO MẬT SUPABASE
-- ============================================================================
ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arenas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.h3_hexagons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.running_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gigo_audit_logs ENABLE ROW LEVEL SECURITY;
-- Vệt GPS lộ nơi ở của Sinh viên: bật RLS, KHÔNG tạo policy, chỉ backend (role postgres) đọc được.
ALTER TABLE public.session_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_avatars ENABLE ROW LEVEL SECURITY;  -- không policy: chỉ backend đọc
ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hall_of_fame ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read universities" ON public.universities;
CREATE POLICY "Public read universities" ON public.universities FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read arenas" ON public.arenas;
CREATE POLICY "Public read arenas" ON public.arenas FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read h3_hexagons" ON public.h3_hexagons;
CREATE POLICY "Public read h3_hexagons" ON public.h3_hexagons FOR SELECT USING (true);

-- users có email: KHÔNG policy (giống session_windows), chỉ backend (role postgres, BYPASSRLS) đọc/ghi.
-- Xếp hạng đọc v_campus_live_scores (không dùng users); client không gọi PostgREST.
DROP POLICY IF EXISTS "Public read users leaderboard" ON public.users;
DROP POLICY IF EXISTS "Users update own profile" ON public.users;

DROP POLICY IF EXISTS "Public read seasons" ON public.seasons;
CREATE POLICY "Public read seasons" ON public.seasons FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read hall_of_fame" ON public.hall_of_fame;
CREATE POLICY "Public read hall_of_fame" ON public.hall_of_fame FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users read own sessions" ON public.running_sessions;
CREATE POLICY "Users read own sessions" ON public.running_sessions
    FOR SELECT USING (auth.uid() = user_id);

-- KHÔNG cho client tự INSERT: Phiên chạy chèn thẳng qua REST sẽ né Anti-GIGO, và
-- finish_stale_sessions() sẽ cộng distance_meters bịa vào km. Chỉ backend (BYPASSRLS) ghi.
DROP POLICY IF EXISTS "Users insert own sessions" ON public.running_sessions;

-- gigo_audit_logs có user_id + detected_at_h3 (ai bị loại, ở đâu): không cho đọc công khai, chỉ backend đọc.
DROP POLICY IF EXISTS "Public read gigo logs for stats" ON public.gigo_audit_logs;

DROP POLICY IF EXISTS "Users insert own gigo logs" ON public.gigo_audit_logs;  -- chỉ backend ghi

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

-- ============================================================================
-- 11. WEB ADMIN: VAI TRÒ, CẤM CHƠI, DUYỆT NHẬT KÝ GIGO, NHẬT KÝ THAO TÁC ADMIN
-- Cấp admin (chạy tay). Email trường đã đăng nhập app:  UPDATE public.users SET role = 'admin' WHERE email = '<email>';
-- Email thường (gmail...), tạo sẵn tài khoản admin không thuộc Trường nào:
--   INSERT INTO public.users (email, display_name, role) VALUES (lower('<email>'), 'Admin', 'admin')
--   ON CONFLICT (email) DO UPDATE SET role = 'admin';
-- ============================================================================
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role VARCHAR(10) NOT NULL DEFAULT 'user';
-- NULL = không bị cấm; cấm vĩnh viễn ghi năm 9999 (TypeORM không đọc được 'infinity').
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS banned_until TIMESTAMP WITH TIME ZONE;

ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS review_status VARCHAR(20) NOT NULL DEFAULT 'pending';
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.gigo_audit_logs ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP WITH TIME ZONE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_role_check') THEN
        ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (role IN ('user', 'admin'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'gigo_review_status_check') THEN
        ALTER TABLE public.gigo_audit_logs ADD CONSTRAINT gigo_review_status_check
            CHECK (review_status IN ('pending', 'confirmed_cheat', 'false_positive'));
    END IF;
END $$;

-- Thống kê của admin lọc/gom theo thời gian.
CREATE INDEX IF NOT EXISTS idx_gigo_created ON public.gigo_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_created ON public.running_sessions(created_at);

CREATE TABLE IF NOT EXISTS public.admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,           -- vd. user.ban, gigo.review, season.update
    target_type VARCHAR(30) NOT NULL,      -- user | gigo_log | season | university | arena
    target_id VARCHAR(64),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_actions_target ON public.admin_actions(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_created ON public.admin_actions(created_at DESC);
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;  -- không policy: chỉ backend đọc/ghi

-- ============================================================================
-- 12. DIỄN ĐÀN: BÀI ĐĂNG (ẢNH + PHIÊN CHẠY ĐÍNH KÈM), TYM, BÌNH LUẬN, BÁO CÁO
-- Ảnh nằm ở Supabase Storage (bucket public `forum`), bảng chỉ lưu đường dẫn.
-- Bật RLS, không policy: chỉ backend đọc/ghi.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.forum_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    -- Trường của tác giả lúc đăng (lọc bảng tin theo Trường / Cụm)
    university_id UUID REFERENCES public.universities(id) ON DELETE SET NULL,
    body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 2000),
    image_paths TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(image_paths) <= 4),
    session_id UUID REFERENCES public.running_sessions(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    edited_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT forum_posts_not_empty CHECK (char_length(body) > 0 OR cardinality(image_paths) > 0)
);
CREATE INDEX IF NOT EXISTS idx_forum_posts_created ON public.forum_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_forum_posts_university ON public.forum_posts(university_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.forum_likes (
    post_id UUID NOT NULL REFERENCES public.forum_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.forum_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.forum_posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    edited_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_forum_comments_post ON public.forum_comments(post_id, created_at);

-- Báo cáo bài (comment_id NULL) hoặc bình luận; mỗi người báo cáo một mục một lần.
CREATE TABLE IF NOT EXISTS public.forum_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.forum_posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES public.forum_comments(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reason VARCHAR(300),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_forum_reports_once
    ON public.forum_reports (post_id, COALESCE(comment_id, '00000000-0000-0000-0000-000000000000'::uuid), reporter_id);
CREATE INDEX IF NOT EXISTS idx_forum_reports_open ON public.forum_reports(created_at DESC) WHERE resolved_at IS NULL;

ALTER TABLE public.forum_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_reports ENABLE ROW LEVEL SECURITY;

-- Bucket ảnh diễn đàn (public đọc; chỉ backend ghi bằng service role). Chỉ có trên Supabase.
DO $$
BEGIN
    IF to_regclass('storage.buckets') IS NOT NULL THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES ('forum', 'forum', true, 1048576, ARRAY['image/jpeg', 'image/png', 'image/webp'])
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;
