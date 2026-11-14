/* eslint-disable no-console */
import * as fs from 'fs';
import * as path from 'path';

import { parseImuLog, stripGps } from '../modules/telemetry/imu-log';
import {
  adviseThresholds,
  evaluateLog,
  LabelSummary,
  LogEvaluation,
  Percentiles,
  summarizeByLabel,
} from '../modules/telemetry/imu-calibration';
import { BIOMETRIC_THRESHOLDS } from '../modules/telemetry/anti-gigo.service';

/**
 * Phân tích log IMU thật để hiệu chỉnh Cổng Sinh trắc (ticket #9).
 *
 *   npm run imu:analyze -- <file.jsonl | thư mục>...            in báo cáo Markdown
 *   npm run imu:analyze -- --json <...>                          in JSON (để lưu/so sánh)
 *   npm run imu:analyze -- --strip-gps <thư mục đích> <...>      chép bản đã bỏ lat/lng
 *
 * Mặc định (không truyền đường dẫn) đọc test-fixtures/imu-logs/.
 */
const DEFAULT_DIR = path.join(__dirname, '..', '..', 'test-fixtures', 'imu-logs');

function main(argv: string[]): number {
  let json = false;
  let stripTo: string | null = null;
  const inputs: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--json') json = true;
    else if (argv[i] === '--strip-gps') stripTo = argv[++i];
    else if (argv[i] === '--help' || argv[i] === '-h') {
      console.log('Dùng: npm run imu:analyze -- [--json] [--strip-gps <thư mục đích>] [file.jsonl|thư mục]...');
      return 0;
    } else inputs.push(argv[i]);
  }

  const files = collectFiles(inputs.length ? inputs : [DEFAULT_DIR]);
  if (files.length === 0) {
    console.error('Không tìm thấy file .jsonl nào.');
    return 1;
  }

  if (stripTo) {
    fs.mkdirSync(stripTo, { recursive: true });
    for (const f of files) {
      const out = path.join(stripTo, path.basename(f));
      fs.writeFileSync(out, stripGps(fs.readFileSync(f, 'utf8')));
      console.log(`Đã bỏ toạ độ: ${out}`);
    }
    return 0;
  }

  const evaluations: LogEvaluation[] = [];
  for (const f of files) {
    try {
      evaluations.push(evaluateLog(path.basename(f), parseImuLog(fs.readFileSync(f, 'utf8'))));
    } catch (e) {
      console.error(`Bỏ qua ${f}: ${(e as Error).message}`);
    }
  }
  const summaries = summarizeByLabel(evaluations);
  const advice = adviseThresholds(summaries);

  if (json) {
    console.log(JSON.stringify({ thresholds: BIOMETRIC_THRESHOLDS, summaries, advice, logs: evaluations.map(compact) }, null, 2));
  } else {
    console.log(renderMarkdown(evaluations, summaries, advice));
  }
  return 0;
}

function collectFiles(inputs: string[]): string[] {
  const out: string[] = [];
  for (const p of inputs) {
    if (!fs.existsSync(p)) {
      console.error(`Không tồn tại: ${p}`);
      continue;
    }
    if (fs.statSync(p).isDirectory()) {
      for (const name of fs.readdirSync(p).sort()) {
        if (name.endsWith('.jsonl')) out.push(path.join(p, name));
      }
    } else out.push(p);
  }
  return out;
}

function compact(e: LogEvaluation) {
  return {
    name: e.name,
    label: e.label,
    note: e.note,
    durationSeconds: e.durationSeconds,
    accelRateHz: round(e.accelRateHz, 1),
    session: e.session,
    windows: e.windows.map((w) => ({
      i: w.index,
      t: round(w.endSeconds, 1),
      speed: round(w.speedMps, 2),
      acc: round(w.accuracyM, 1),
      applied: w.biometric.applied,
      pass: w.biometric.isValid,
      cadence: w.biometric.analysis.cadenceSpm,
      amp: w.biometric.analysis.amplitudeG,
      prom: w.biometric.analysis.peakProminence,
      kinematic: w.kinematic.errorCode,
    })),
  };
}

export function renderMarkdown(
  evaluations: LogEvaluation[],
  summaries: LabelSummary[],
  advice: ReturnType<typeof adviseThresholds>,
): string {
  const t = BIOMETRIC_THRESHOLDS;
  const lines: string[] = [];
  lines.push('# Hiệu chỉnh Cổng Sinh trắc bằng mẫu IMU thật');
  lines.push('');
  lines.push(
    `Ngưỡng hiện tại: xét khi >= ${t.minSpeedMps} m/s; Nhịp bước >= ${t.minCadenceSpm} SPM; ` +
      `biên độ >= ${t.minAmplitudeG}G; độ rõ đỉnh >= ${t.minPeakProminence}.`,
  );
  lines.push('');
  lines.push('## Từng log');
  lines.push('');
  lines.push('| File | Nhãn | Ghi chú | Thời lượng | IMU Hz | Cửa sổ (được xét) | Qua cổng | Phiên |');
  lines.push('|---|---|---|---|---|---|---|---|');
  for (const e of evaluations) {
    const applied = e.windows.filter((w) => w.biometric.applied);
    const passed = applied.filter((w) => w.biometric.isValid).length;
    const s = e.session;
    const outcome = s.rejected
      ? `bị loại ${s.code} lúc ${round(s.atSeconds, 1)} s${s.byKinematic ? ' (GPS)' : ''}`
      : 'không bị loại';
    lines.push(
      `| ${e.name} | ${e.label} | ${e.note || '-'} | ${fmtDuration(e.durationSeconds)} | ${round(e.accelRateHz, 1)} | ` +
        `${e.windows.length} (${applied.length}) | ${applied.length ? pct(passed / applied.length) : '-'} | ${outcome} |`,
    );
  }
  lines.push('');
  lines.push('## Theo nhãn (chỉ tính cửa sổ được xét, tức >= 2,5 m/s)');
  lines.push('');
  lines.push('| Nhãn | Log | Cửa sổ (được xét) | Qua cổng | ERR_202 | Trượt GPS | Phiên bị loại | Nhịp bước p5/trung vị/p95 | Biên độ G | Độ rõ đỉnh |');
  lines.push('|---|---|---|---|---|---|---|---|---|---|');
  for (const s of summaries) {
    lines.push(
      `| ${s.label} | ${s.logs} | ${s.windows} (${s.appliedWindows}) | ${pct(s.biometricPassRate)} | ${pct(s.biometricFailRate)} | ` +
        `${s.kinematicFailures} | ${s.sessionsRejected}/${s.logs} | ${fmtP(s.cadenceSpm)} | ${fmtP(s.amplitudeG)} | ${fmtP(s.peakProminence)} |`,
    );
  }
  lines.push('');
  lines.push('## Gợi ý ngưỡng (p5 chạy bộ so với p95 xe máy)');
  lines.push('');
  lines.push('| Chỉ số | Hiện tại | p5 chạy bộ | p95 xe máy | Gợi ý | Nhận xét |');
  lines.push('|---|---|---|---|---|---|');
  for (const a of advice) {
    lines.push(
      `| ${a.metric} | ${a.current} | ${a.runP5 ?? '-'} | ${a.motorbikeP95 ?? '-'} | ${a.suggested ?? '-'} | ${a.verdict} |`,
    );
  }
  return lines.join('\n');
}

function fmtP(p: Percentiles | null): string {
  return p ? `${p.p5} / ${p.median} / ${p.p95}` : '-';
}

function fmtDuration(s: number): string {
  return `${Math.floor(s / 60)}m${String(Math.round(s % 60)).padStart(2, '0')}s`;
}

function pct(x: number): string {
  return `${Math.round(x * 100)}%`;
}

function round(x: number, d: number): number {
  const f = 10 ** d;
  return Math.round(x * f) / f;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
