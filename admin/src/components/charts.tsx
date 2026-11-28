import type { ReactNode } from 'react'
import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'

const AXIS = { tickLine: false, tick: { fontSize: 11, fill: 'var(--muted-foreground)' } } as const

export interface Series {
  key: string
  label: string
  color: string
}

interface TipProps {
  active?: boolean
  label?: string | number
  payload?: { dataKey?: string | number; value?: number | null }[]
  series: Series[]
  fmtLabel: (l: string | number) => string
  fmtValue: (v: number) => string
}

function Tip({ active, label, payload, series, fmtLabel, fmtValue }: TipProps) {
  if (!active || !payload?.length || label === undefined) return null
  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs shadow-md">
      <div className="mb-1 font-medium">{fmtLabel(label)}</div>
      {series.map((s) => {
        const v = payload.find((p) => p.dataKey === s.key)?.value
        return (
          <div key={s.key} className="flex items-center gap-2">
            <span className="size-2 rounded-sm" style={{ background: s.color }} aria-hidden />
            <span className="text-muted-foreground">{s.label}</span>
            <span className="ml-auto pl-3 font-medium tabular-nums">{v == null ? '—' : fmtValue(v)}</span>
          </div>
        )
      })}
    </div>
  )
}

/** Khung biểu đồ: tiêu đề nói rõ đơn vị; ≥ 2 series thì có chú giải. */
export function ChartCard({ title, unit, series, children }: { title: string; unit?: string; series?: Series[]; children: ReactNode }) {
  return (
    <figure className="min-w-0 rounded-lg border bg-card p-4">
      <figcaption className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm font-medium">
          {title} {unit && <span className="font-normal text-muted-foreground">({unit})</span>}
        </span>
        {series && series.length > 1 && (
          <ul className="flex gap-3 text-xs text-muted-foreground">
            {series.map((s) => (
              <li key={s.key} className="flex items-center gap-1.5">
                <span className="size-2.5 rounded-sm" style={{ background: s.color }} aria-hidden />
                {s.label}
              </li>
            ))}
          </ul>
        )}
      </figcaption>
      <div className="h-56">{children}</div>
    </figure>
  )
}

/** Cột (có thể chồng): một trục y, khe 2px giữa các phần chồng. */
export function Bars({
  data,
  x,
  series,
  fmtX = String,
  fmtLabel = String,
  fmtValue = (v) => v.toLocaleString('vi-VN'),
  stacked,
}: {
  data: object[]
  x: string
  series: Series[]
  fmtX?: (v: string | number) => string
  fmtLabel?: (v: string | number) => string
  fmtValue?: (v: number) => string
  stacked?: boolean
}) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={data} margin={{ top: 6, right: 4, bottom: 0, left: -16 }} barCategoryGap="20%">
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey={x} {...AXIS} axisLine={{ stroke: 'var(--border)' }} tickFormatter={fmtX} minTickGap={8} />
        <YAxis {...AXIS} axisLine={false} allowDecimals={false} width={40} />
        <Tooltip
          cursor={{ fill: 'var(--muted)', opacity: 0.6 }}
          content={(p) => <Tip {...(p as unknown as TipProps)} series={series} fmtLabel={fmtLabel} fmtValue={fmtValue} />}
        />
        {series.map((s, i) => (
          <Bar
            key={s.key}
            dataKey={s.key}
            stackId={stacked ? 'a' : undefined}
            fill={s.color}
            stroke="var(--card)"
            strokeWidth={stacked ? 1 : 0}
            radius={!stacked || i === series.length - 1 ? [4, 4, 0, 0] : 0}
            isAnimationActive={false}
          />
        ))}
      </BarChart>
    </ResponsiveContainer>
  )
}

export function Lines({
  data,
  x,
  series,
  fmtX = String,
  fmtLabel = String,
  fmtValue = (v) => v.toLocaleString('vi-VN'),
  yFormatter,
  yDomain,
}: {
  data: object[]
  x: string
  series: Series[]
  fmtX?: (v: string | number) => string
  fmtLabel?: (v: string | number) => string
  fmtValue?: (v: number) => string
  yFormatter?: (v: number) => string
  yDomain?: [number, number | 'auto']
}) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <LineChart data={data} margin={{ top: 6, right: 8, bottom: 0, left: -16 }}>
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey={x} {...AXIS} axisLine={{ stroke: 'var(--border)' }} tickFormatter={fmtX} minTickGap={12} />
        <YAxis {...AXIS} axisLine={false} width={44} tickFormatter={yFormatter} domain={yDomain} allowDecimals={false} />
        <Tooltip
          cursor={{ stroke: 'var(--muted-foreground)', strokeDasharray: '3 3' }}
          content={(p) => <Tip {...(p as unknown as TipProps)} series={series} fmtLabel={fmtLabel} fmtValue={fmtValue} />}
        />
        {series.map((s) => (
          <Line key={s.key} type="linear" dataKey={s.key} stroke={s.color} strokeWidth={2} dot={false} activeDot={{ r: 4 }} connectNulls={false} isAnimationActive={false} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  )
}
