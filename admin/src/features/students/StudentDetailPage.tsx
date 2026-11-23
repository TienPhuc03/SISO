import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, ImageOff, ShieldAlert, ShieldCheck, UserRound } from 'lucide-react'
import { toast } from 'sonner'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { DataTable } from '@/components/DataTable'
import { StatTile } from '@/components/StatTile'
import { BanBadge, Pill, RunBadge, UniversityTag } from '@/components/status'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { errorMessage, get, http, send } from '@/lib/api'
import { fmtDateTime, fmtDuration, fmtKm, fmtNumber, isBannedNow, isPermanentBan, rejectionLabel } from '@/lib/format'
import type { Page, RunStatus } from '@/lib/types'
import { BanButton } from '@/features/anti-cheat/BanDialog'
import { ActionsTable } from '@/features/actions/ActionsPage'
import type { Student } from './StudentsPage'

interface StudentDetail extends Student {
  universityName: string | null
  completedSessions: number
  rejectedSessions: number
  completedMeters: number
}
interface SessionRow {
  sessionId: string
  status: RunStatus
  sessionType: string
  distanceMeters: number
  durationSeconds: number
  hexCount: number
  rejectionReason: string | null
  startedAt: string
}

/** Ảnh đại diện cần JWT nên tải bằng axios rồi tạo object URL; `v` tránh bản cache 1 năm sau khi gỡ ảnh. */
function Avatar({ userId, version }: { userId: string; version: number }) {
  const [url, setUrl] = useState<string | null>(null)
  useEffect(() => {
    let revoked: string | null = null
    http
      .get(`/profile/avatar/${userId}`, { params: { v: version }, responseType: 'blob' })
      .then((r) => setUrl((revoked = URL.createObjectURL(r.data))))
      .catch(() => setUrl(null))
    return () => {
      if (revoked) URL.revokeObjectURL(revoked)
    }
  }, [userId, version])
  return url ? (
    <img src={url} alt="Ảnh đại diện" className="size-16 rounded-full border object-cover" />
  ) : (
    <div className="grid size-16 place-items-center rounded-full border bg-muted text-muted-foreground">
      <UserRound className="size-7" aria-hidden />
    </div>
  )
}

export function StudentDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [page, setPage] = useState(1)
  const student = useQuery({ queryKey: ['students', 'detail', id], queryFn: () => get<StudentDetail>(`/admin/users/${id}`) })
  const sessions = useQuery({
    queryKey: ['students', 'sessions', id, page],
    queryFn: () => get<Page<SessionRow>>(`/admin/users/${id}/sessions`, { page, limit: 10 }),
  })

  const columns = useMemo<ColumnDef<SessionRow>[]>(
    () => [
      { header: 'Bắt đầu', cell: ({ row }) => <span className="whitespace-nowrap tabular-nums">{fmtDateTime(row.original.startedAt)}</span> },
      { header: 'Loại', cell: ({ row }) => (row.original.sessionType === 'ARENA_LOOP' ? 'Chạy khép vòng' : 'Chạy tự do') },
      { header: 'Trạng thái', cell: ({ row }) => <RunBadge status={row.original.status} /> },
      { header: 'Quãng đường', cell: ({ row }) => <span className="tabular-nums">{fmtKm(row.original.distanceMeters)}</span> },
      { header: 'Thời gian', cell: ({ row }) => <span className="tabular-nums">{fmtDuration(row.original.durationSeconds)}</span> },
      { header: 'Ô đất', cell: ({ row }) => <span className="tabular-nums">{row.original.hexCount}</span> },
      {
        header: 'Lý do loại',
        cell: ({ row }) =>
          row.original.rejectionReason ? (
            <span className="text-xs">
              <span className="font-mono">{row.original.rejectionReason}</span> · {rejectionLabel(row.original.rejectionReason)}
            </span>
          ) : (
            <span className="text-muted-foreground">—</span>
          ),
      },
    ],
    [],
  )

  if (student.isLoading) return <Skeleton className="h-40 w-full" />
  if (student.isError || !student.data)
    return (
      <p role="alert" className="text-destructive">
        {errorMessage(student.error)}
      </p>
    )
  const s = student.data
  const banned = isBannedNow(s.bannedUntil)

  return (
    <>
      <Button variant="ghost" size="sm" className="mb-3 -ml-2" onClick={() => (window.history.length > 1 ? navigate(-1) : navigate('/students'))}>
        <ArrowLeft aria-hidden /> Quay lại
      </Button>

      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div className="flex items-center gap-4">
          <Avatar userId={s.id} version={student.dataUpdatedAt} />
          <div>
            <h1 className="flex flex-wrap items-center gap-2 text-2xl font-semibold tracking-tight">
              {s.displayName}
              {s.role === 'admin' && <Pill tone="info" icon={ShieldCheck}>Admin</Pill>}
              <BanBadge until={s.bannedUntil} />
            </h1>
            <p className="text-sm text-muted-foreground">{s.email}</p>
            <div className="mt-1 flex items-center gap-2 text-sm">
              <UniversityTag code={s.universityCode} color={s.universityColor} />
              <span className="text-muted-foreground">{s.universityName}</span>
            </div>
            {banned && (
              <p className="mt-1 text-sm text-destructive">
                {isPermanentBan(s.bannedUntil) ? 'Bị khoá vĩnh viễn.' : `Bị khoá đến ${fmtDateTime(s.bannedUntil)}.`}
              </p>
            )}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {s.hasAvatar && (
            <ConfirmDialog
              title="Gỡ ảnh đại diện?"
              description={`Ảnh của ${s.email} bị xoá; Sinh viên có thể tải ảnh khác. Thao tác được ghi vào Nhật ký admin.`}
              confirmLabel="Gỡ ảnh"
              onConfirm={() =>
                send('delete', `/admin/users/${s.id}/avatar`)
                  .then(() => {
                    qc.invalidateQueries({ queryKey: ['students'] })
                    qc.invalidateQueries({ queryKey: ['actions'] })
                    toast.success('Đã gỡ ảnh đại diện.')
                  })
                  .catch((e) => {
                    toast.error(errorMessage(e))
                    throw e
                  })
              }
              trigger={
                <Button variant="outline" size="sm">
                  <ImageOff aria-hidden /> Gỡ ảnh đại diện
                </Button>
              }
            />
          )}
          {s.role !== 'admin' && <BanButton user={s} />}
        </div>
      </div>

      <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <StatTile label="Km cá nhân (Mùa này)" value={fmtNumber(s.personalKm, 2)} />
        <StatTile label="Phiên chạy" value={s.sessions} sub={`Hợp lệ ${s.completedSessions} · Bị loại ${s.rejectedSessions}`} />
        <StatTile label="Tổng km hợp lệ (mọi Mùa)" value={fmtNumber(s.completedMeters / 1000, 2)} />
        <StatTile
          label="Vi phạm GIGO"
          value={s.violations}
          tone={s.violations ? 'danger' : undefined}
          to={s.violations ? `/anti-cheat?user=${s.id}` : undefined}
          sub={s.violations ? 'Xem nhật ký' : 'Không tính báo nhầm'}
        />
        <StatTile label="Chạy gần nhất" value={<span className="text-base">{fmtDateTime(s.lastRunAt)}</span>} />
        <StatTile label="Tham gia" value={<span className="text-base">{fmtDateTime(s.createdAt)}</span>} />
      </div>

      <section className="mb-6" aria-labelledby="runs-title">
        <h2 id="runs-title" className="mb-3 text-base font-semibold">
          Lịch sử Phiên chạy
        </h2>
        <DataTable
          columns={columns}
          data={sessions.data?.items}
          loading={sessions.isLoading}
          page={page}
          limit={10}
          total={sessions.data?.total}
          onPage={setPage}
          onRowClick={(r) => navigate(`/sessions/${r.sessionId}`)}
          empty="Sinh viên chưa có Phiên chạy nào."
        />
      </section>

      <section aria-labelledby="acts-title">
        <h2 id="acts-title" className="mb-3 flex items-center gap-2 text-base font-semibold">
          <ShieldAlert className="size-4" aria-hidden /> Thao tác admin lên tài khoản này
        </h2>
        <ActionsTable targetType="user" targetId={s.id} />
        <p className="mt-2 text-xs text-muted-foreground">
          Toàn bộ nhật ký ở <Link to="/actions" className="underline">Nhật ký admin</Link>.
        </p>
      </section>
    </>
  )
}
