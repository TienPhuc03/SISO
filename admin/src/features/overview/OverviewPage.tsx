import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { PageHeader } from '@/components/PageHeader'
import { StatTile } from '@/components/StatTile'
import { DataTable } from '@/components/DataTable'
import { Bars, ChartCard, Lines } from '@/components/charts'
import { UniversityTag } from '@/components/status'
import { Skeleton } from '@/components/ui/skeleton'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { get } from '@/lib/api'
import { fmtDateTime, fmtKm, fmtNumber } from '@/lib/format'

interface Overview {
  dau: number
  wau: number
  mau: number
  totalUsers: number
  newUsersToday: number
  newUsers7d: number
  sessionsToday: number
  rejectedToday: number
  stuckSessions: number
  pendingReviews: number
  bannedUsers: number
}
interface Daily {
  day: string
  sessions: number
  rejected: number
  activeUsers: number
  newUsers: number
}
interface Hourly {
  hour: number
  sessions: number
  rejected: number
}
interface Stuck {
  sessionId: string
  sessionType: string
  distanceMeters: number
  startedAt: string
  lastWindowAt: string
  email: string
  displayName: string
  universityCode: string | null
  universityColor: string | null
}

const dayLabel = (d: string | number) => {
  const [, m, day] = String(d).split('-')
  return `${day}/${m}`
}

export function OverviewPage() {
  const navigate = useNavigate()
  const [days, setDays] = useState('30')
  const overview = useQuery({ queryKey: ['stats', 'overview'], queryFn: () => get<Overview>('/admin/stats/overview'), refetchInterval: 60_000 })
  const daily = useQuery({ queryKey: ['stats', 'daily', days], queryFn: () => get<Daily[]>('/admin/stats/daily', { days }) })
  const hourly = useQuery({ queryKey: ['stats', 'hour', days], queryFn: () => get<Hourly[]>('/admin/stats/by-hour', { days }) })
  const stuck = useQuery({ queryKey: ['stats', 'stuck'], queryFn: () => get<Stuck[]>('/admin/stats/stuck-sessions') })

  const dailyRows = useMemo(
    () =>
      (daily.data ?? []).map((d) => ({
        ...d,
        valid: d.sessions - d.rejected,
        // Ngày không có Phiên nào: để trống thay vì 0% cho khỏi hiểu nhầm.
        rejectRate: d.sessions ? (d.rejected / d.sessions) * 100 : null,
      })),
    [daily.data],
  )
  const hourRows = useMemo(() => (hourly.data ?? []).map((h) => ({ ...h, valid: h.sessions - h.rejected })), [hourly.data])

  const o = overview.data
  const stuckColumns = useMemo<ColumnDef<Stuck>[]>(
    () => [
      {
        header: 'Sinh viên',
        cell: ({ row }) => (
          <div>
            <div className="font-medium">{row.original.displayName}</div>
            <div className="text-xs text-muted-foreground">{row.original.email}</div>
          </div>
        ),
      },
      { header: 'Trường', cell: ({ row }) => <UniversityTag code={row.original.universityCode} color={row.original.universityColor} /> },
      { header: 'Bắt đầu', cell: ({ row }) => <span className="tabular-nums">{fmtDateTime(row.original.startedAt)}</span> },
      { header: 'Cửa sổ cuối', cell: ({ row }) => <span className="tabular-nums">{fmtDateTime(row.original.lastWindowAt)}</span> },
      { header: 'Quãng đường', cell: ({ row }) => <span className="tabular-nums">{fmtKm(row.original.distanceMeters)}</span> },
    ],
    [],
  )

  return (
    <>
      <PageHeader
        title="Tổng quan"
        description="Sinh viên hoạt động = có ít nhất một Phiên chạy trong khoảng thời gian. Ngày giờ theo giờ Việt Nam."
        actions={
          <Tabs value={days} onValueChange={setDays}>
            <TabsList aria-label="Khoảng thời gian của biểu đồ">
              <TabsTrigger value="7">7 ngày</TabsTrigger>
              <TabsTrigger value="30">30 ngày</TabsTrigger>
              <TabsTrigger value="90">90 ngày</TabsTrigger>
            </TabsList>
          </Tabs>
        }
      />

      {!o ? (
        <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
          {Array.from({ length: 8 }, (_, i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
      ) : (
        <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
          <StatTile label="Hoạt động hôm nay (DAU)" value={o.dau} sub={`trên ${o.totalUsers} Sinh viên`} />
          <StatTile label="Hoạt động 7 ngày (WAU)" value={o.wau} sub={`30 ngày: ${o.mau}`} />
          <StatTile label="Sinh viên mới hôm nay" value={o.newUsersToday} sub={`7 ngày: ${o.newUsers7d}`} />
          <StatTile
            label="Phiên chạy hôm nay"
            value={o.sessionsToday}
            sub={`Bị loại: ${o.rejectedToday}${o.sessionsToday ? ` (${fmtNumber((o.rejectedToday / o.sessionsToday) * 100)}%)` : ''}`}
          />
          <StatTile label="Phiên bị kẹt (> 2 giờ)" value={o.stuckSessions} tone={o.stuckSessions ? 'warn' : undefined} sub="Vẫn ACTIVE, chưa kết thúc" />
          <StatTile label="Nhật ký chờ duyệt" value={o.pendingReviews} tone={o.pendingReviews ? 'warn' : undefined} to="/anti-cheat?review=pending" sub="Mở Chống gian lận" />
          <StatTile label="Đang bị khoá" value={o.bannedUsers} to="/students?status=banned" sub="Mở danh sách" />
          <StatTile label="Tổng Sinh viên" value={o.totalUsers} />
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <ChartCard title="Sinh viên hoạt động theo ngày" unit="người">
          <Lines data={dailyRows} x="day" fmtX={dayLabel} fmtLabel={dayLabel} series={[{ key: 'activeUsers', label: 'Hoạt động', color: 'var(--chart-4)' }]} />
        </ChartCard>
        <ChartCard
          title="Phiên chạy theo ngày"
          unit="phiên"
          series={[
            { key: 'valid', label: 'Không bị loại', color: 'var(--chart-5)' },
            { key: 'rejected', label: 'Bị loại', color: 'var(--chart-2)' },
          ]}
        >
          <Bars
            stacked
            data={dailyRows}
            x="day"
            fmtX={dayLabel}
            fmtLabel={dayLabel}
            series={[
              { key: 'valid', label: 'Không bị loại', color: 'var(--chart-5)' },
              { key: 'rejected', label: 'Bị loại', color: 'var(--chart-2)' },
            ]}
          />
        </ChartCard>
        <ChartCard title="Tỉ lệ Phiên bị loại theo ngày" unit="%">
          <Lines
            data={dailyRows}
            x="day"
            fmtX={dayLabel}
            fmtLabel={dayLabel}
            fmtValue={(v) => `${fmtNumber(v)}%`}
            yFormatter={(v) => `${v}%`}
            yDomain={[0, 'auto']}
            series={[{ key: 'rejectRate', label: 'Bị loại', color: 'var(--chart-2)' }]}
          />
        </ChartCard>
        <ChartCard title="Sinh viên mới theo ngày" unit="người">
          <Bars data={dailyRows} x="day" fmtX={dayLabel} fmtLabel={dayLabel} series={[{ key: 'newUsers', label: 'Sinh viên mới', color: 'var(--chart-4)' }]} />
        </ChartCard>
        <div className="lg:col-span-2">
          <ChartCard
            title={`Phiên chạy theo giờ trong ngày, gộp ${days} ngày`}
            unit="phiên"
            series={[
              { key: 'valid', label: 'Không bị loại', color: 'var(--chart-5)' },
              { key: 'rejected', label: 'Bị loại', color: 'var(--chart-2)' },
            ]}
          >
            <Bars
              stacked
              data={hourRows}
              x="hour"
              fmtX={(h) => `${h}h`}
              fmtLabel={(h) => `${h}:00 – ${h}:59`}
              series={[
                { key: 'valid', label: 'Không bị loại', color: 'var(--chart-5)' },
                { key: 'rejected', label: 'Bị loại', color: 'var(--chart-2)' },
              ]}
            />
          </ChartCard>
        </div>
      </div>

      <section className="mt-6" aria-labelledby="stuck-title">
        <h2 id="stuck-title" className="mb-1 text-base font-semibold">
          Phiên chạy bị kẹt
        </h2>
        <p className="mb-3 text-sm text-muted-foreground">
          Vẫn ACTIVE sau hơn 2 giờ. Bình thường cron <code className="text-xs">finish_stale_sessions</code> tự kết thúc sau 30 phút không có cửa sổ mới;
          còn dòng ở đây nghĩa là cron chưa chạy.
        </p>
        <DataTable
          columns={stuckColumns}
          data={stuck.data}
          loading={stuck.isLoading}
          empty="Không có Phiên chạy nào bị kẹt."
          onRowClick={(s) => navigate(`/sessions/${s.sessionId}`)}
        />
      </section>
    </>
  )
}
