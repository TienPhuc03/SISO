import * as fs from 'fs';
import * as path from 'path';

import { evaluateLog, LogEvaluation, summarizeByLabel } from './imu-calibration';
import { parseImuLog, ImuLogLabel } from './imu-log';

/**
 * Cổng Sinh trắc trên MẪU IMU THẬT (ticket #9). Đọc mọi log trong `backend/test-fixtures/imu-logs/`
 * (bản đã bỏ toạ độ). Chưa có log của nhãn nào thì các test của nhãn đó được bỏ qua.
 *
 * Tiêu chí (chốt ở #9):
 * - Chạy bộ: >= 90% cửa sổ được xét qua cổng; không Phiên chạy nào bị loại vì ERR_202.
 * - Xe máy: >= 90% cửa sổ được xét bị ERR_202; mọi phiên đủ dài bị loại trong ~30 s
 *   (6 cửa sổ) kể từ cửa sổ đầu tiên được xét.
 * - Đi bộ: không phiên nào bị loại vì ERR_202.
 */
const FIXTURE_DIR = path.join(__dirname, '..', '..', '..', 'test-fixtures', 'imu-logs');
export const MIN_RUN_PASS_RATE = 0.9;
export const MIN_MOTORBIKE_FAIL_RATE = 0.9;
/** 6 cửa sổ x 5,12 s ~ 30 s. */
export const MOTORBIKE_REJECT_WITHIN_WINDOWS = 6;

function loadEvaluations(): LogEvaluation[] {
  if (!fs.existsSync(FIXTURE_DIR)) return [];
  return fs
    .readdirSync(FIXTURE_DIR)
    .filter((f) => f.endsWith('.jsonl'))
    .sort()
    .map((f) => evaluateLog(f, parseImuLog(fs.readFileSync(path.join(FIXTURE_DIR, f), 'utf8'))));
}

const evaluations = loadEvaluations();
const byLabel = (label: ImuLogLabel) => evaluations.filter((e) => e.label === label);
const appliedCount = (evs: LogEvaluation[]) =>
  evs.flatMap((e) => e.windows).filter((w) => w.biometric.applied).length;

/** Chỉ chạy khi có đủ dữ liệu; nếu không thì hiện rõ lý do bỏ qua trong kết quả Jest. */
const itWhen = (cond: boolean) => (cond ? it : it.skip);

describe('Cổng Sinh trắc trên mẫu IMU thật (test-fixtures/imu-logs)', () => {
  const run = byLabel('run');
  const walk = byLabel('walk');
  const moto = byLabel('motorbike');
  const summaries = summarizeByLabel(evaluations);
  const summaryOf = (label: ImuLogLabel) => summaries.find((s) => s.label === label);

  describe('Chạy bộ', () => {
    itWhen(appliedCount(run) > 0)(
      `>= ${MIN_RUN_PASS_RATE * 100}% cửa sổ được xét qua cổng (cần log nhãn "run" có tốc độ >= 2,5 m/s)`,
      () => {
        expect(summaryOf('run').biometricPassRate).toBeGreaterThanOrEqual(MIN_RUN_PASS_RATE);
      },
    );

    itWhen(run.length > 0)('không Phiên chạy bộ nào bị loại vì ERR_202', () => {
      const wronglyRejected = run.filter((e) => e.session.rejected && e.session.code === 'ERR_202');
      expect(wronglyRejected.map((e) => `${e.name} lúc ${e.session.atSeconds}s`)).toEqual([]);
    });
  });

  describe('Xe máy', () => {
    itWhen(appliedCount(moto) > 0)(
      `>= ${MIN_MOTORBIKE_FAIL_RATE * 100}% cửa sổ được xét bị ERR_202 (cần log nhãn "motorbike" >= 2,5 m/s)`,
      () => {
        expect(summaryOf('motorbike').biometricFailRate).toBeGreaterThanOrEqual(MIN_MOTORBIKE_FAIL_RATE);
      },
    );

    const longEnough = moto.filter(
      (e) => e.windows.filter((w) => w.biometric.applied).length >= MOTORBIKE_REJECT_WITHIN_WINDOWS,
    );
    itWhen(longEnough.length > 0)(
      `mỗi phiên xe máy bị loại trong ${MOTORBIKE_REJECT_WITHIN_WINDOWS} cửa sổ (~30 s) kể từ khi đủ tốc độ`,
      () => {
        const late = longEnough.filter((e) => {
          const firstApplied = e.windows.find((w) => w.biometric.applied).index;
          return (
            !e.session.rejected || e.session.atWindow - firstApplied >= MOTORBIKE_REJECT_WITHIN_WINDOWS
          );
        });
        expect(late.map((e) => `${e.name}: ${e.session.rejected ? `loại ở cửa sổ ${e.session.atWindow}` : 'không bị loại'}`)).toEqual([]);
      },
    );
  });

  describe('Đi bộ', () => {
    itWhen(walk.length > 0)('không phiên đi bộ nào bị loại vì ERR_202', () => {
      expect(walk.filter((e) => e.session.code === 'ERR_202').map((e) => e.name)).toEqual([]);
    });
  });

  it('mọi log trong thư mục đều đọc được và đủ ít nhất 1 cửa sổ', () => {
    expect(evaluations.filter((e) => e.windows.length === 0).map((e) => e.name)).toEqual([]);
  });
});
