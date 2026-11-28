import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Gavel } from 'lucide-react'
import { BanBadge, ReviewBadge, RunBadge, UniversityTag } from '@/components/status'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { errorMessage, get } from '@/lib/api'
import { fmtDateTime, fmtDuration, fmtKm, fmtNumber, kmh, rejectionLabel } from '@/lib/format'
import type { GigoLog, SessionDetail } from '@/lib/types'
import { BanButton } from './BanDialog'
import { ReviewDialog } from './ReviewDialog'
import { RouteMap } from './RouteMap'
import { WindowCharts } from './WindowCharts'

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-lg border bg-card px-4 py-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="mt-1 text-lg font-semibold tabular-nums">{value}</div>
    </div>
  )
}

export function SessionDetailPage() {
  const { id } = useParams()
  const [reviewing, setReviewing] = useState<GigoLog | null>(null)
  const q = useQuery({ queryKey: ['session', id], queryFn: () => get<SessionDetail>(`/admin/sessions/${id}`) })

  if (q.isLoading)
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-80 w-full" />
      </div>
    )
  if (q.isError || !q.data)
    return (
      <div className="space-y-3">
        <BackLink />
        <p role="alert" className="text-destructive">{errorMessage(q.error)}</p>
      </div>
    )

  const { session: s, user, auditLogs } = q.data
  const failed = s.windows.filter((w) => !w.passed).length

  return (
    <>
      <BackLink />
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="flex flex-wrap items-center gap-2 text-2xl font-semibold tracking-tight">
            Phiên chạy <RunBadge status={s.status} />
          </h1>
          <p className="num mt-1 text-xs text-muted-foreground">{s.sessionId}</p>
          {s.rejectionReason && (
            <p className="mt-1 text-sm">
              Lý do loại: <span className="num font-medium">{s.rejectionReason}</span> · {rejectionLabel(s.rejectionReason)}
            </p>
          )}
        </div>
        {user && (
          <Card className="gap-2 py-3">
            <CardContent className="flex items-center gap-4 px-4">
              <div>
                <div className="flex items-center gap-2 font-medium">
                  {user.displayName} <BanBadge until={user.bannedUntil} />
                </div>
                <div className="text-xs text-muted-foreground">{user.email}</div>
                <UniversityTag code={user.universityCode} color={user.universityColor} />
              </div>
              <BanButton user={user} />
            </CardContent>
          </Card>
        )}
      </div>

      <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <Stat label="Quãng đường kiểm định" value={fmtKm(s.distanceMeters)} />
        <Stat label="Thời gian chạy" value={fmtDuration(s.durationSeconds)} />
        <Stat label="Cửa sổ đạt / nghi ngờ" value={`${s.windows.length - failed} / ${failed}`} />
        <Stat label="Loại" value={s.sessionType === 'ARENA_LOOP' ? 'Chạy khép vòng' : 'Chạy tự do'} />
        <Stat label="Bắt đầu" value={<span className="text-sm">{fmtDateTime(s.startedAt)}</span>} />
        <Stat label="Kết thúc" value={<span className="text-sm">{fmtDateTime(s.finishedAt)}</span>} />
      </div>

      <div className="grid gap-6 xl:grid-cols-5">
        <Card className="xl:col-span-3">
          <CardHeader>
            <CardTitle className="text-base">Đường chạy</CardTitle>
          </CardHeader>
          <CardContent>
            <RouteMap windows={s.windows} />
          </CardContent>
        </Card>
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle className="text-base">Nhật ký GIGO của Phiên</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {auditLogs.length === 0 && <p className="text-sm text-muted-foreground">Phiên chạy này không bị ghi nhật ký GIGO.</p>}
            {auditLogs.map((l) => (
              <div key={l.id} className="rounded-md border p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <span className="num font-medium">{l.rejectionType}</span>
                    <ReviewBadge status={l.reviewStatus} />
                  </div>
                  <Button variant="outline" size="sm" onClick={() => setReviewing(l)}>
                    <Gavel aria-hidden /> Duyệt
                  </Button>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{rejectionLabel(l.rejectionType)}</p>
                <dl className="num mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
                  <dt className="text-muted-foreground">Tốc độ GPS</dt>
                  <dd>{fmtNumber(kmh(l.gpsSpeedMps))} km/h</dd>
                  <dt className="text-muted-foreground">Nhịp bước</dt>
                  <dd>{l.cadenceSpm} spm</dd>
                  <dt className="text-muted-foreground">Năng lượng dọc</dt>
                  <dd>{l.verticalEnergyG == null ? '—' : `${fmtNumber(l.verticalEnergyG, 3)} G`}</dd>
                  <dt className="text-muted-foreground">Sai số GPS</dt>
                  <dd>{l.gpsAccuracyM == null ? '—' : `${fmtNumber(l.gpsAccuracyM)} m`}</dd>
                  <dt className="text-muted-foreground">Ghi lúc</dt>
                  <dd>{fmtDateTime(l.createdAt)}</dd>
                  {l.reviewedByEmail && (
                    <>
                      <dt className="text-muted-foreground">Duyệt bởi</dt>
                      <dd className="truncate">{l.reviewedByEmail}</dd>
                    </>
                  )}
                </dl>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="text-base">Theo cửa sổ (5,12 giây)</CardTitle>
        </CardHeader>
        <CardContent>
          {s.windows.length ? <WindowCharts windows={s.windows} /> : <p className="text-sm text-muted-foreground">Chưa có cửa sổ nào.</p>}
          <details className="mt-4">
            <summary className="cursor-pointer text-sm font-medium">Xem dạng bảng</summary>
            <div className="mt-2 max-h-80 overflow-auto rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Seq</TableHead>
                    <TableHead>Thời điểm</TableHead>
                    <TableHead>Tốc độ (km/h)</TableHead>
                    <TableHead>Nhịp bước</TableHead>
                    <TableHead>Điểm GPS</TableHead>
                    <TableHead>Kết quả</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody className="num">
                  {s.windows.map((w) => (
                    <TableRow key={w.seq}>
                      <TableCell>{w.seq}</TableCell>
                      <TableCell>{fmtDateTime(w.recordedAt)}</TableCell>
                      <TableCell>{fmtNumber(kmh(w.speedMps))}</TableCell>
                      <TableCell>{w.cadenceSpm}</TableCell>
                      <TableCell>{w.points.length}</TableCell>
                      <TableCell className={w.passed ? '' : 'font-medium text-warn'}>{w.passed ? 'Đạt' : '▲ Nghi ngờ'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </details>
        </CardContent>
      </Card>

      <ReviewDialog log={reviewing} onClose={() => setReviewing(null)} />
    </>
  )
}

/** Phiên chạy được mở từ nhiều trang (Chống gian lận, Sinh viên, Tổng quan): quay lại trang trước nếu có. */
function BackLink() {
  const navigate = useNavigate()
  return (
    <Button variant="ghost" size="sm" className="mb-3 -ml-2" onClick={() => (window.history.length > 1 ? navigate(-1) : navigate('/anti-cheat'))}>
      <ArrowLeft aria-hidden /> Quay lại
    </Button>
  )
}
