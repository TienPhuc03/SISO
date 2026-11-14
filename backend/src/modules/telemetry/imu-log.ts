import { IMU_WINDOW_SIZE, ImuSampleDto } from './dto/telemetry-payload.dto';

/**
 * Đọc file log GPS/IMU thật do app ghi (màn "Ghi log cảm biến", issue #8) và cắt thành cửa sổ
 * giống hệt phía app (`buildReplayWindows` trong `replay_telemetry_source.dart`).
 * Định dạng: `assets/telemetry_logs/README.md` (JSON Lines, `k` = h | a | g).
 */

export type ImuLogLabel = 'run' | 'walk' | 'motorbike' | 'other';

export interface ImuLogHeader {
  v: number;
  startedAt: string;
  label: ImuLogLabel;
  note: string;
  device: string;
  platform: string;
}

export interface ImuLogAccel {
  t: number;
  x: number;
  y: number;
  z: number;
}

export interface ImuLogGps {
  t: number;
  /** Có thể vắng ở bản đã bỏ toạ độ (`stripGps`). */
  lat?: number;
  lng?: number;
  acc: number;
  /** m/s; iOS trả -1 khi chưa có tốc độ. */
  spd: number;
  mock: boolean;
}

export interface ImuLog {
  header: ImuLogHeader;
  accel: ImuLogAccel[];
  gps: ImuLogGps[];
}

/** Sai số dùng khi log không có GPS: cố ý > 20 m (server báo ERR_203), giống phía app. */
export const NO_GPS_ACCURACY_M = 999;

const LABELS: ImuLogLabel[] = ['run', 'walk', 'motorbike', 'other'];

export function parseImuLog(content: string): ImuLog {
  let header: ImuLogHeader | undefined;
  const accel: ImuLogAccel[] = [];
  const gps: ImuLogGps[] = [];

  content.split(/\r?\n/).forEach((raw, i) => {
    const line = raw.trim();
    if (!line) return;
    let rec: Record<string, unknown>;
    try {
      rec = JSON.parse(line);
    } catch (e) {
      throw new Error(`Dòng ${i + 1} của log không phải JSON: ${(e as Error).message}`);
    }
    switch (rec.k) {
      case 'h':
        header = {
          v: Number(rec.v ?? 1),
          startedAt: String(rec.startedAt ?? ''),
          label: LABELS.includes(rec.label as ImuLogLabel) ? (rec.label as ImuLogLabel) : 'other',
          note: String(rec.note ?? ''),
          device: String(rec.device ?? ''),
          platform: String(rec.platform ?? ''),
        };
        break;
      case 'a':
        accel.push({ t: num(rec.t, i), x: num(rec.x, i), y: num(rec.y, i), z: num(rec.z, i) });
        break;
      case 'g':
        gps.push({
          t: num(rec.t, i),
          ...(rec.lat !== undefined ? { lat: num(rec.lat, i) } : {}),
          ...(rec.lng !== undefined ? { lng: num(rec.lng, i) } : {}),
          acc: num(rec.acc, i),
          spd: num(rec.spd, i),
          mock: rec.mock === true,
        });
        break;
      default:
        break; // loại bản ghi lạ: bỏ qua
    }
  });

  if (!header) throw new Error('Log thiếu dòng header {"k":"h"}.');
  accel.sort((a, b) => a.t - b.t);
  gps.sort((a, b) => a.t - b.t);
  return { header, accel, gps };
}

/** Bản dùng để commit: bỏ lat/lng, giữ gia tốc, tốc độ, sai số GPS. */
export function stripGps(content: string): string {
  return (
    content
      .split(/\r?\n/)
      .filter((l) => l.trim())
      .map((line) => {
        const rec = JSON.parse(line);
        if (rec.k === 'g') {
          delete rec.lat;
          delete rec.lng;
        }
        return JSON.stringify(rec);
      })
      .join('\n') + '\n'
  );
}

export interface ImuLogWindow {
  /** Thứ tự cửa sổ trong log, từ 0. */
  index: number;
  startT: number;
  endT: number;
  samples: ImuSampleDto[];
  averageSpeedMps: number;
  horizontalAccuracy: number;
  isMocked: boolean;
}

/**
 * Cửa sổ 256 mẫu liên tiếp, không chồng nhau, bỏ phần lẻ cuối. Tốc độ = trung bình GPS hợp lệ
 * trong khoảng (không có thì lấy lần gần nhất trước đó, không nữa thì 0); sai số = tệ nhất;
 * mock nếu có bất kỳ lần nào.
 */
export function buildImuWindows(log: ImuLog, baseEpochMs = 0): ImuLogWindow[] {
  const windows: ImuLogWindow[] = [];
  for (let start = 0, index = 0; start + IMU_WINDOW_SIZE <= log.accel.length; start += IMU_WINDOW_SIZE, index++) {
    const chunk = log.accel.slice(start, start + IMU_WINDOW_SIZE);
    const t0 = chunk[0].t;
    const t1 = chunk[chunk.length - 1].t;

    let gps = log.gps.filter((g) => g.t >= t0 && g.t <= t1);
    if (gps.length === 0) {
      const before = log.gps.filter((g) => g.t < t0);
      if (before.length > 0) gps = [before[before.length - 1]];
    }
    const speeds = gps.map((g) => g.spd).filter((s) => s >= 0);

    windows.push({
      index,
      startT: t0,
      endT: t1,
      samples: chunk.map((a) => ({ ax: a.x, ay: a.y, az: a.z, timestamp: baseEpochMs + a.t })),
      averageSpeedMps: speeds.length === 0 ? 0 : speeds.reduce((s, v) => s + v, 0) / speeds.length,
      horizontalAccuracy: gps.length === 0 ? NO_GPS_ACCURACY_M : Math.max(...gps.map((g) => g.acc)),
      isMocked: gps.some((g) => g.mock),
    });
  }
  return windows;
}

/** Tần số gia tốc kế thực tế của cả log (Hz). */
export function accelRateHz(log: ImuLog): number {
  const n = log.accel.length;
  if (n < 2) return 0;
  const span = log.accel[n - 1].t - log.accel[0].t;
  return span > 0 ? ((n - 1) * 1000) / span : 0;
}

function num(v: unknown, line: number): number {
  const n = typeof v === 'number' ? v : NaN;
  if (!Number.isFinite(n)) throw new Error(`Dòng ${line + 1} của log thiếu số hợp lệ.`);
  return n;
}
