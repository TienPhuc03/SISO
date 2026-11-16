-- ============================================================================
-- SISO — TỰ ĐỘNG HOÁ MÙA GIẢI VÀ HAO MÒN (MODULE 8, SRS FR-08 / BR06 / MỤC 20-21)
--
-- Chạy file này RIÊNG trong Supabase SQL Editor, sau init_schema.sql. Chạy lại an toàn.
-- Đừng chạy lại init_schema.sql chỉ để có phần này: file đó ghi đè ranh giới Đấu trường.
--
-- Hàm nằm ở schema `private` (không lộ qua Data API của Supabase): nếu để ở `public`,
-- bất kỳ ai có anon key đều có thể gọi /rpc để xoá trắng bản đồ.
--
-- Kiểm tra sau khi chạy:
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'siso_%';
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
--
-- Thử reset thủ công (Ngày 26, TC-08). CẢNH BÁO: xoá trắng bản đồ và km thật:
--   SELECT private.close_finished_season(p_force => true);
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;

-- Mỗi Mùa giải có tối đa một Quán quân; chặn ghi trùng ở tầng dữ liệu.
CREATE UNIQUE INDEX IF NOT EXISTS uq_hof_season ON public.hall_of_fame(season_number);

-- Mùa 1 trong seed đã hết hạn (31/10) khi chưa từng thi đấu thật. Nếu giữ nguyên, lần chạy
-- cron đầu tiên sẽ đóng mùa và xoá bản đồ ngay; kéo về cuối tháng hiện tại để tránh việc đó.
UPDATE public.seasons
SET end_date = (date_trunc('month', (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')) + interval '1 month - 1 day')::date
WHERE is_active
  AND end_date < (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;

-- ----------------------------------------------------------------------------
-- Đóng Mùa giải đã hết hạn: ghi Quán quân, xoá trắng Lãnh thổ và Km, mở Mùa mới.
-- Toàn bộ nằm trong một transaction của lời gọi hàm. Mùa chưa hết hạn thì không làm gì,
-- nên chạy mỗi ngày vẫn đúng và tự bù được nếu lần chạy đầu tháng bị lỡ.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.close_finished_season(p_force boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;
    v_season public.seasons%ROWTYPE;
    v_champion record;
    v_next_number int;
    v_cleared_hexes int;
BEGIN
    SELECT * INTO v_season
    FROM public.seasons
    WHERE is_active
    ORDER BY season_number DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('closed', false, 'reason', 'no_active_season');
    END IF;

    IF NOT p_force AND v_season.end_date >= v_today THEN
        RETURN jsonb_build_object('closed', false, 'reason', 'season_still_running',
                                  'season', v_season.season_number);
    END IF;

    -- Hoà điểm: ưu tiên % Đất, rồi % Km, cuối cùng theo mã trường để kết quả luôn xác định.
    -- Mùa không có hoạt động nào (điểm 0) thì không có Quán quân.
    SELECT university_id, territory_pct, mileage_pct, composite_power_pct INTO v_champion
    FROM public.v_campus_live_scores
    WHERE composite_power_pct > 0
    ORDER BY composite_power_pct DESC, territory_pct DESC, mileage_pct DESC, short_code ASC
    LIMIT 1;

    IF FOUND THEN
        INSERT INTO public.hall_of_fame
            (season_number, champion_university_id, territory_pct, mileage_pct, composite_power_pct)
        VALUES
            (v_season.season_number, v_champion.university_id, v_champion.territory_pct,
             v_champion.mileage_pct, v_champion.composite_power_pct)
        ON CONFLICT (season_number) DO NOTHING;
    END IF;

    UPDATE public.h3_hexagons
    SET owner_university_id = NULL, shield_hp = 0, updated_at = now()
    WHERE owner_university_id IS NOT NULL OR shield_hp <> 0;
    GET DIAGNOSTICS v_cleared_hexes = ROW_COUNT;

    UPDATE public.universities SET total_season_km = 0 WHERE total_season_km <> 0;
    UPDATE public.users SET personal_km = 0 WHERE personal_km <> 0;

    UPDATE public.seasons SET is_active = false WHERE season_number = v_season.season_number;

    SELECT max(season_number) + 1 INTO v_next_number FROM public.seasons;
    INSERT INTO public.seasons (season_number, start_date, end_date, is_active)
    VALUES (
        v_next_number,
        v_today,
        (date_trunc('month', v_today::timestamp) + interval '1 month - 1 day')::date,
        true
    );

    RETURN jsonb_build_object(
        'closed', true,
        'season', v_season.season_number,
        'champion', v_champion.university_id,
        'cleared_hexes', v_cleared_hexes,
        'next_season', v_next_number
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- Hao mòn: không được Tuần tra 24 giờ thì Độ bền còn 50, 48 giờ thì Ô đất về Trung lập.
-- Tính theo last_patrolled_at nên chạy lại nhiều lần vẫn cho cùng kết quả.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.decay_hexagons()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_neutralized int;
    v_weakened int;
BEGIN
    UPDATE public.h3_hexagons
    SET owner_university_id = NULL, shield_hp = 0, updated_at = now()
    WHERE owner_university_id IS NOT NULL
      AND last_patrolled_at <= now() - interval '48 hours';
    GET DIAGNOSTICS v_neutralized = ROW_COUNT;

    UPDATE public.h3_hexagons
    SET shield_hp = 50, updated_at = now()
    WHERE owner_university_id IS NOT NULL
      AND shield_hp > 50
      AND last_patrolled_at <= now() - interval '24 hours';
    GET DIAGNOSTICS v_weakened = ROW_COUNT;

    RETURN jsonb_build_object('neutralized', v_neutralized, 'weakened', v_weakened);
END;
$$;

REVOKE ALL ON FUNCTION private.close_finished_season(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.decay_hexagons() FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- Lịch chạy. pg_cron trên Supabase dùng giờ UTC: 17:00 UTC = 00:00 Việt Nam (UTC+7).
-- cron.schedule cập nhật job cùng tên nên chạy lại file không tạo job trùng.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('siso_close_finished_season', '0 17 * * *',
                              'SELECT private.close_finished_season();');
        PERFORM cron.schedule('siso_decay_hexagons', '0 * * * *',
                              'SELECT private.decay_hexagons();');
    ELSE
        RAISE NOTICE 'pg_cron chưa được bật: bỏ qua việc đặt lịch (các hàm vẫn dùng được).';
    END IF;
END $$;
