import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { FilterX, Gavel } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { DataTable } from '@/components/DataTable'
import { BanBadge, ReviewBadge, RunBadge, UniversityTag } from '@/components/status'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { get } from '@/lib/api'
import { REJECTION_LABELS, dayStartIso, fmtDateTime, fmtNumber, kmh, nextDayStartIso, rejectionLabel } from '@/lib/format'
import type { GigoLog, Offender, Page } from '@/lib/types'
import { useUniversities } from './api'
import { BanButton } from './BanDialog'
import { ReviewDialog } from './ReviewDialog'

const ALL = 'all'
const PAGE_SIZE = 20

export function AntiCheatPage() {
  const [params, setParams] = useSearchParams()
  const navigate = useNavigate()
  const [reviewing, setReviewing] = useState<GigoLog | null>(null)
  const [days, setDays] = useState<'7' | '30'>('7')
  const { data: universities } = useUniversities()

  const f = {
    type: params.get('type') ?? '',
    universityId: params.get('uni') ?? '',
    userId: params.get('user') ?? '',
    reviewStatus: params.get('review') ?? '',
    from: params.get('from') ?? '',
    to: params.get('to') ?? '',
    page: Number(params.get('page') ?? 1),
  }
  const setFilter = (key: string, value: string) => {
    const next = new URLSearchParams(params)
    if (value && value !== ALL) next.set(key, value)
    else next.delete(key)
    if (key !== 'page') next.delete('page')
    setParams(next, { replace: true })
  }
  const hasFilter = ['type', 'uni', 'user', 'review', 'from', 'to'].some((k) => params.has(k))

  const logs = useQuery({
    queryKey: ['gigo-logs', f],
    queryFn: () =>
      get<Page<GigoLog>>('/admin/gigo-logs', {
        type: f.type,
        universityId: f.universityId,
        userId: f.userId,
        reviewStatus: f.reviewStatus,
        from: f.from && dayStartIso(f.from),
        to: f.to && nextDayStartIso(f.to),
        page: f.page,
        limit: PAGE_SIZE,
      }),
    placeholderData: keepPreviousData,
  })

  const offenders = useQuery({
    queryKey: ['offenders', days],
    queryFn: () => get<Offender[]>('/admin/gigo-logs/top-offenders', { days, limit: 10 }),
  })

  const columns = useMemo<ColumnDef<GigoLog>[]>(
    () => [
      { header: 'Thời gian', cell: ({ row }) => <span className="num whitespace-nowrap text-sm">{fmtDateTime(row.original.createdAt)}</span> },
      {
        header: 'Sinh viên',
        cell: ({ row }) => (
          <div className="min-w-40">
            <div className="flex items-center gap-2 font-medium">
              {row.original.displayName}
              <BanBadge until={row.original.bannedUntil} />
            </div>
            <div className="text-xs text-muted-foreground">{row.original.email}</div>
          </div>
        ),
      },
      { header: 'Trường', cell: ({ row }) => <UniversityTag code={row.original.universityCode} color={row.original.universityColor} /> },
      {
        header: 'Vi phạm',
        cell: ({ row }) => (
          <div className="whitespace-nowrap">
            <span className="num text-sm font-medium">{row.original.rejectionType}</span>
            <div className="text-xs text-muted-foreground">{rejectionLabel(row.original.rejectionType)}</div>
          </div>
        ),
      },
      { header: 'Tốc độ', cell: ({ row }) => <span className="num">{fmtNumber(kmh(row.original.gpsSpeedMps))} km/h</span> },
      { header: 'Nhịp bước', cell: ({ row }) => <span className="num">{row.original.cadenceSpm} spm</span> },
      { header: 'Phiên chạy', cell: ({ row }) => <RunBadge status={row.original.sessionStatus} /> },
      { header: 'Duyệt', cell: ({ row }) => <ReviewBadge status={row.original.reviewStatus} /> },
      {
        id: 'actions',
        header: () => <span className="sr-only">Thao tác</span>,
        cell: ({ row }) => (
          <Button
            variant="outline"
            size="sm"
            onClick={(e) => {
              e.stopPropagation()
              setReviewing(row.original)
            }}
          >
            <Gavel aria-hidden /> Duyệt
          </Button>
        ),
      },
    ],
    [],
  )

  const offenderColumns = useMemo<ColumnDef<Offender>[]>(
    () => [
      { header: '#', cell: ({ row }) => <span className="num text-muted-foreground">{row.index + 1}</span> },
      {
        header: 'Sinh viên',
        cell: ({ row }) => (
          <div className="min-w-40">
            <div className="flex items-center gap-2 font-medium">
              {row.original.displayName}
              <BanBadge until={row.original.bannedUntil} />
            </div>
            <div className="text-xs text-muted-foreground">{row.original.email}</div>
          </div>
        ),
      },
      { header: 'Trường', cell: ({ row }) => <UniversityTag code={row.original.universityCode} color={row.original.universityColor} /> },
      { header: 'Vi phạm', cell: ({ row }) => <span className="num font-semibold">{row.original.violations}</span> },
      { header: 'Đã xác nhận', cell: ({ row }) => <span className="num">{row.original.confirmed}</span> },
      { header: 'Chờ duyệt', cell: ({ row }) => <span className="num">{row.original.pending}</span> },
      { header: 'Loại', cell: ({ row }) => <span className="num text-xs">{row.original.types.join(', ')}</span> },
      { header: 'Lần cuối', cell: ({ row }) => <span className="num whitespace-nowrap text-sm">{fmtDateTime(row.original.lastAt)}</span> },
      {
        id: 'actions',
        header: () => <span className="sr-only">Thao tác</span>,
        cell: ({ row }) => <BanButton user={{ id: row.original.userId, email: row.original.email, bannedUntil: row.original.bannedUntil }} />,
      },
    ],
    [],
  )

  return (
    <>
      <PageHeader title="Chống gian lận" description="Nhật ký GIGO do server ghi khi loại Phiên chạy; duyệt kết luận và khoá Sinh viên." />

      <Card className="mb-6 gap-3 py-4">
        <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2 px-4">
          <CardTitle className="text-base">Vi phạm nhiều nhất</CardTitle>
          <Tabs value={days} onValueChange={(v) => setDays(v as '7' | '30')}>
            <TabsList>
              <TabsTrigger value="7">7 ngày</TabsTrigger>
              <TabsTrigger value="30">30 ngày</TabsTrigger>
            </TabsList>
          </Tabs>
        </CardHeader>
        <CardContent className="px-4">
          <DataTable
            columns={offenderColumns}
            data={offenders.data}
            loading={offenders.isLoading}
            empty={`Không có vi phạm nào trong ${days} ngày qua.`}
            onRowClick={(o) => setFilter('user', o.userId)}
          />
          <p className="mt-2 text-xs text-muted-foreground">Không tính nhật ký đã kết luận báo nhầm. Bấm một dòng để lọc nhật ký của Sinh viên đó.</p>
        </CardContent>
      </Card>

      <section aria-labelledby="logs-title">
        <h2 id="logs-title" className="mb-3 text-base font-semibold">
          Nhật ký GIGO
        </h2>
        <div className="mb-3 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          <FilterSelect label="Loại vi phạm" value={f.type} onChange={(v) => setFilter('type', v)}>
            {Object.entries(REJECTION_LABELS)
              .filter(([code]) => code !== 'ERR_106')
              .map(([code, label]) => (
                <SelectItem key={code} value={code}>
                  {code} · {label}
                </SelectItem>
              ))}
          </FilterSelect>
          <FilterSelect label="Trường" value={f.universityId} onChange={(v) => setFilter('uni', v)}>
            {universities?.map((u) => (
              <SelectItem key={u.id} value={u.id}>
                {u.shortCode}
              </SelectItem>
            ))}
          </FilterSelect>
          <FilterSelect label="Trạng thái duyệt" value={f.reviewStatus} onChange={(v) => setFilter('review', v)}>
            <SelectItem value="pending">Chờ duyệt</SelectItem>
            <SelectItem value="confirmed_cheat">Gian lận</SelectItem>
            <SelectItem value="false_positive">Báo nhầm</SelectItem>
          </FilterSelect>
          <div className="space-y-1.5">
            <Label htmlFor="f-from" className="text-xs text-muted-foreground">
              Từ ngày
            </Label>
            <Input id="f-from" type="date" value={f.from} max={f.to || undefined} onChange={(e) => setFilter('from', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="f-to" className="text-xs text-muted-foreground">
              Đến ngày
            </Label>
            <Input id="f-to" type="date" value={f.to} min={f.from || undefined} onChange={(e) => setFilter('to', e.target.value)} />
          </div>
          <div className="flex items-end">
            <Button variant="ghost" className="w-full" disabled={!hasFilter} onClick={() => setParams({}, { replace: true })}>
              <FilterX aria-hidden /> Xoá bộ lọc
            </Button>
          </div>
        </div>
        {f.userId && (
          <p className="mb-3 text-sm text-muted-foreground">
            Đang lọc theo một Sinh viên.{' '}
            <Button variant="link" className="h-auto p-0" onClick={() => setFilter('user', '')}>
              Bỏ lọc
            </Button>
          </p>
        )}
        <DataTable
          columns={columns}
          data={logs.data?.items}
          loading={logs.isLoading}
          page={f.page}
          limit={PAGE_SIZE}
          total={logs.data?.total}
          onPage={(p) => setFilter('page', String(p))}
          onRowClick={(l) => l.sessionId && navigate(`/sessions/${l.sessionId}`)}
          empty="Không có nhật ký nào khớp bộ lọc."
        />
        <p className="mt-2 text-xs text-muted-foreground">Bấm một dòng có Phiên chạy để xem Đường chạy và biểu đồ theo cửa sổ.</p>
      </section>

      <ReviewDialog log={reviewing} onClose={() => setReviewing(null)} />
    </>
  )
}

function FilterSelect({
  label,
  value,
  onChange,
  children,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  children: React.ReactNode
}) {
  const id = `f-${label}`
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="text-xs text-muted-foreground">
        {label}
      </Label>
      <Select value={value || ALL} onValueChange={onChange}>
        <SelectTrigger id={id} className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL}>Tất cả</SelectItem>
          {children}
        </SelectContent>
      </Select>
    </div>
  )
}
