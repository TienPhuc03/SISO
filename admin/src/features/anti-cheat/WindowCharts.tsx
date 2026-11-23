import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { fmtNumber, kmh } from '@/lib/format'
import type { SessionWindow } from '@/lib/types'

interface Point {
  seq: number
  value: number
  passed: boolean
}

/** Điểm đạt: tròn; nghi ngờ: tam giác màu cảnh báo (hình dạng khác nhau, không chỉ màu). */
function Dot(props: { cx?: number; cy?: number; payload?: Point }) {
  const { cx, cy, payload } = props
  if (cx == null || cy == null || !payload) return null
  if (payload.passed) return <circle cx={cx} cy={cy} r={4} fill="var(--primary)" stroke="var(--card)" strokeWidth={2} />
  return <path d={`M${cx},${cy - 6} L${cx + 6},${cy + 5} L${cx - 6},${cy + 5} Z`} fill="var(--warn)" stroke="var(--card)" strokeWidth={2} />
}

function Tip({ active, payload, unit }: { active?: boolean; payload?: { payload: Point }[]; unit: string }) {
  const p = payload?.[0]?.payload
  if (!active || !p) return null
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <div className="font-medium">Cửa sổ #{p.seq}</div>
      <div className="num">
        {fmtNumber(p.value)} {unit}
      </div>
      <div className={p.passed ? 'text-muted-foreground' : 'font-medium text-warn'}>{p.passed ? 'Đạt' : '▲ Nghi ngờ (không qua Cổng Sinh trắc)'}</div>
    </div>
  )
}

function SeqChart({ title, unit, data }: { title: string; unit: string; data: Point[] }) {
  return (
    <figure className="min-w-0">
      <figcaption className="mb-1 text-sm font-medium">
        {title} <span className="font-normal text-muted-foreground">({unit})</span>
      </figcaption>
      <div className="h-48">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 10, right: 12, bottom: 4, left: -8 }}>
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis dataKey="seq" tickLine={false} axisLine={{ stroke: 'var(--border)' }} tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} />
            <YAxis tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} width={44} />
            <Tooltip content={(props) => <Tip active={props.active} payload={props.payload as unknown as { payload: Point }[]} unit={unit} />} cursor={{ stroke: 'var(--muted-foreground)', strokeDasharray: '3 3' }} />
            <Line type="linear" dataKey="value" stroke="var(--primary)" strokeWidth={2} dot={<Dot />} activeDot={{ r: 6 }} isAnimationActive={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </figure>
  )
}

/** Tốc độ và Nhịp bước theo seq: hai biểu đồ riêng (không dùng trục kép). */
export function WindowCharts({ windows }: { windows: SessionWindow[] }) {
  return (
    <div className="grid gap-6 md:grid-cols-2">
      <SeqChart title="Tốc độ GPS" unit="km/h" data={windows.map((w) => ({ seq: w.seq, value: kmh(w.speedMps), passed: w.passed }))} />
      <SeqChart title="Nhịp bước" unit="bước/phút" data={windows.map((w) => ({ seq: w.seq, value: w.cadenceSpm, passed: w.passed }))} />
    </div>
  )
}
