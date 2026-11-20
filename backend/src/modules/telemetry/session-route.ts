import * as h3 from 'h3-js';
import { GpsPoint } from '../../entities/session-window.entity';
import { MAX_GPS_ACCURACY_M, MAX_HUMAN_SPEED_MPS } from './anti-gigo.service';

/** Hai điểm cách nhau lâu hơn mức này (Tạm dừng hoặc mất tín hiệu) thì vẽ thành hai đoạn riêng. */
export const ROUTE_GAP_MS = 15_000;

const trusted = (p: GpsPoint) => p.accuracy >= 0 && p.accuracy <= MAX_GPS_ACCURACY_M;

export interface MultiLineString {
  type: 'MultiLineString';
  coordinates: number[][][];
}

/**
 * Ghép vệt GPS của các cửa sổ thành Đường chạy GeoJSON ([lng, lat]), tách đoạn ở chỗ ngắt > [gapMs].
 * Bỏ điểm sai số âm hoặc > 20 m (cùng ngưỡng Cổng Động học) và đoạn chỉ có một điểm.
 */
export function buildRoute(windows: { gps_points: GpsPoint[] }[], gapMs = ROUTE_GAP_MS): MultiLineString {
  const points = windows
    .flatMap((w) => w.gps_points)
    .filter(trusted)
    .sort((a, b) => a.timestamp - b.timestamp);

  const segments: number[][][] = [];
  let current: number[][] = [];
  let lastTs = -Infinity;
  for (const p of points) {
    if (p.timestamp - lastTs > gapMs && current.length) {
      segments.push(current);
      current = [];
    }
    current.push([p.lng, p.lat]);
    lastTs = p.timestamp;
  }
  segments.push(current);

  return { type: 'MultiLineString', coordinates: segments.filter((s) => s.length >= 2) };
}

/**
 * Chỉ giữ điểm GPS đáng tin và đi tới được từ điểm giữ trước đó với tốc độ ≤ sức người.
 * [anchor] là điểm cuối đã lưu của Cửa sổ trước (null ở Cửa sổ đầu). Điểm bị bỏ không làm điểm neo,
 * nên toạ độ bịa / dịch chuyển tức thời không kéo được Đường chạy đi xa; GPS nhiễu một điểm tự hồi phục.
 * shortcut: không nới theo sai số GPS (nới mỗi bước thì cộng dồn được), nên GPS rung mạnh có thể làm thưa
 * Đường chạy; hiệu chỉnh bằng dữ liệu thực địa.
 */
export function filterPlausiblePoints(points: GpsPoint[], anchor: GpsPoint | null): GpsPoint[] {
  const kept: GpsPoint[] = [];
  let last = anchor;
  for (const p of points.filter(trusted).sort((a, b) => a.timestamp - b.timestamp)) {
    if (last) {
      const meters = h3.greatCircleDistance([last.lat, last.lng], [p.lat, p.lng], h3.UNITS.m);
      const seconds = (p.timestamp - last.timestamp) / 1000;
      if (seconds < 0 || meters > MAX_HUMAN_SPEED_MPS * seconds) continue;
    }
    kept.push(p);
    last = p;
  }
  return kept;
}
