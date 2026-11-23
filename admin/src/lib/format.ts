const TZ = 'Asia/Ho_Chi_Minh'

export const fmtDateTime = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('vi-VN', { timeZone: TZ, dateStyle: 'short', timeStyle: 'short' }) : '—'

export const fmtNumber = (n: number | null | undefined, digits = 1) =>
  n === null || n === undefined ? '—' : n.toLocaleString('vi-VN', { maximumFractionDigits: digits })

export const fmtKm = (meters: number | null | undefined) => (meters == null ? '—' : `${fmtNumber(meters / 1000, 2)} km`)

export const fmtDuration = (s: number) => {
  const m = Math.floor(s / 60)
  return m >= 60 ? `${Math.floor(m / 60)} giờ ${m % 60} phút` : `${m} phút ${s % 60} giây`
}

/** m/s -> km/h, dễ đọc hơn cho admin. */
export const kmh = (mps: number) => mps * 3.6

/** Khoá vĩnh viễn được lưu là năm 9999. */
export const isPermanentBan = (iso: string | null) => !!iso && new Date(iso).getUTCFullYear() >= 9999
export const isBannedNow = (iso: string | null) => !!iso && new Date(iso) > new Date()

/** Mã loại Phiên / vi phạm -> mô tả cho admin. */
export const REJECTION_LABELS: Record<string, string> = {
  ERR_201: 'GPS giả lập',
  ERR_202: 'Xe máy / vượt tốc độ người',
  ERR_205: 'Sai chữ ký / gửi lại cửa sổ',
  ERR_106: 'Bị khoá khi đang chạy',
}
export const rejectionLabel = (code: string | null | undefined) => (code ? (REJECTION_LABELS[code] ?? code) : '—')

/** YYYY-MM-DD (giờ VN) của ô <input type="date"> -> mốc ISO đầu ngày giờ VN. */
export const dayStartIso = (day: string) => `${day}T00:00:00+07:00`
export const nextDayStartIso = (day: string) => {
  const d = new Date(`${day}T00:00:00+07:00`)
  d.setUTCDate(d.getUTCDate() + 1)
  return d.toISOString()
}
