import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { PushService, universityTopic } from './push.service';

/** Ô đất về Trung lập sau 48 giờ không Tuần tra. GIỮ KHỚP với private.decay_hexagons(). */
export const NEUTRAL_AFTER_HOURS = 48;
export const REMIND_BEFORE_HOURS = 6;
const HOUR_MS = 60 * 60 * 1000;

const AT_RISK_HEXES_SQL = `
  SELECT owner_university_id AS university_id, COUNT(*)::int AS count
  FROM public.h3_hexagons
  WHERE owner_university_id IS NOT NULL
    AND last_patrolled_at > $1 AND last_patrolled_at <= $2
  GROUP BY owner_university_id`;

/**
 * Mỗi giờ nhắc các trường có Ô đất còn khoảng 6 giờ nữa là về Trung lập.
 * Khung xét rộng đúng 1 giờ nên mỗi Ô chỉ được nhắc một lần cho mỗi lần Tuần tra, không cần lưu "đã nhắc".
 */
@Injectable()
export class PatrolReminderService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PatrolReminderService.name);
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly dataSource: DataSource,
    private readonly push: PushService,
  ) {}

  onModuleInit() {
    if (!this.push.enabled) return;
    // shortcut: hẹn giờ trong một tiến trình; chạy nhiều instance backend thì sẽ gửi trùng, khi đó chuyển sang pg_cron hoặc hàng đợi.
    // Server tắt quá 1 giờ thì các Ô rơi vào khung lúc đó không được nhắc (chấp nhận được với lời nhắc).
    this.timer = setInterval(() => {
      this.remind().catch((e) => this.logger.error(`Nhắc Tuần tra lỗi: ${e}`));
    }, HOUR_MS);
  }

  onModuleDestroy() {
    clearInterval(this.timer);
  }

  /** Gửi một thông báo cho mỗi trường có Ô đất vừa lọt vào khung nhắc; trả số trường đã gửi được. */
  async remind(now = new Date()): Promise<number> {
    const to = new Date(now.getTime() - (NEUTRAL_AFTER_HOURS - REMIND_BEFORE_HOURS) * HOUR_MS);
    const from = new Date(to.getTime() - HOUR_MS);
    const rows: { university_id: string; count: number }[] = await this.dataSource.query(
      AT_RISK_HEXES_SQL,
      [from, to],
    );

    let sent = 0;
    for (const row of rows) {
      try {
        await this.push.sendToTopic(
          universityTopic(row.university_id),
          'Ô đất sắp về Trung lập',
          `${row.count} Ô đất của trường bạn sẽ về Trung lập trong khoảng ${REMIND_BEFORE_HOURS} giờ nữa. Tuần tra ngay để giữ đất!`,
          { type: 'patrol_reminder', count: String(row.count) },
        );
        sent++;
      } catch (e) {
        // Một trường lỗi không chặn các trường còn lại
        this.logger.error(`Gửi nhắc Tuần tra cho trường ${row.university_id} lỗi: ${e}`);
      }
    }
    return sent;
  }
}
