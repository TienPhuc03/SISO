import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { PageHeader } from '@/components/PageHeader'
import { DataTable } from '@/components/DataTable'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { get } from '@/lib/api'
import { fmtDateTime } from '@/lib/format'
import type { Page } from '@/lib/types'

interface AdminAction {
  id: string
  action: string
  targetType: string
  targetId: string | null
  payload: Record<string, unknown>
  createdAt: string
  adminEmail: string | null
}

const ACTION_LABELS: Record<string, string> = {
  'user.ban': 'Khoá Sinh viên',
  'user.unban': 'Gỡ khoá Sinh viên',
  'user.avatar_remove': 'Gỡ ảnh đại diện',
  'gigo.review': 'Duyệt nhật ký GIGO',
  'season.create': 'Tạo Mùa giải',
  'season.update': 'Sửa Mùa giải',
  'season.delete': 'Xoá Mùa giải',
  'university.create': 'Thêm Trường',
  'university.update': 'Sửa Trường',
  'university.delete': 'Xoá Trường',
  'arena.update': 'Sửa Đấu trường',
  'university.verify': 'Duyệt Trường',
  'university.merge': 'Gộp Trường',
  'forum.post.delete': 'Xoá bài diễn đàn',
  'forum.comment.delete': 'Xoá bình luận',
  'forum.report.dismiss': 'Bỏ qua báo cáo',
}
const TARGETS: Record<string, string> = { user: 'Sinh viên', gigo_log: 'Nhật ký GIGO', season: 'Mùa giải', university: 'Trường', arena: 'Đấu trường', forum_post: 'Bài diễn đàn', forum_comment: 'Bình luận', forum_report: 'Báo cáo diễn đàn' }

function Target({ a }: { a: AdminAction }) {
  if (a.targetType === 'user' && a.targetId)
    return (
      <Link to={`/students/${a.targetId}`} className="underline underline-offset-2">
        Xem Sinh viên
      </Link>
    )
  const sessionId = a.payload?.sessionId
  if (a.targetType === 'gigo_log' && typeof sessionId === 'string')
    return (
      <Link to={`/sessions/${sessionId}`} className="underline underline-offset-2">
        Xem Phiên chạy
      </Link>
    )
  return <span className="font-mono text-xs text-muted-foreground">{a.targetId ?? '—'}</span>
}

/** Bảng nhật ký thao tác admin, có thể giới hạn theo một đối tượng (vd. trang chi tiết Sinh viên). */
export function ActionsTable({ targetType, targetId }: { targetType?: string; targetId?: string }) {
  const [page, setPage] = useState(1)
  const q = useQuery({
    queryKey: ['actions', targetType, targetId, page],
    queryFn: () => get<Page<AdminAction>>('/admin/actions', { targetType, targetId, page, limit: 20 }),
    placeholderData: keepPreviousData,
  })
  const columns = useMemo<ColumnDef<AdminAction>[]>(
    () => [
      { header: 'Thời gian', cell: ({ row }) => <span className="whitespace-nowrap tabular-nums">{fmtDateTime(row.original.createdAt)}</span> },
      { header: 'Admin', cell: ({ row }) => <span className="text-sm">{row.original.adminEmail ?? '—'}</span> },
      { header: 'Thao tác', cell: ({ row }) => <span className="font-medium">{ACTION_LABELS[row.original.action] ?? row.original.action}</span> },
      { header: 'Đối tượng', cell: ({ row }) => <Target a={row.original} /> },
      {
        header: 'Chi tiết',
        cell: ({ row }) => (
          <code className="block max-w-md truncate text-xs text-muted-foreground" title={JSON.stringify(row.original.payload)}>
            {JSON.stringify(row.original.payload)}
          </code>
        ),
      },
    ],
    [],
  )
  return (
    <DataTable
      columns={columns}
      data={q.data?.items}
      loading={q.isLoading}
      page={page}
      limit={20}
      total={q.data?.total}
      onPage={setPage}
      empty="Chưa có thao tác nào."
    />
  )
}

export function ActionsPage() {
  const [target, setTarget] = useState('all')
  return (
    <>
      <PageHeader title="Nhật ký admin" description="Mọi thao tác thay đổi dữ liệu của admin: khoá, duyệt vi phạm, sửa Mùa giải / Trường / Đấu trường, gỡ ảnh." />
      <div className="mb-3 w-56 space-y-1.5">
        <Label htmlFor="a-target" className="text-xs text-muted-foreground">
          Loại đối tượng
        </Label>
        <Select value={target} onValueChange={setTarget}>
          <SelectTrigger id="a-target" className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tất cả</SelectItem>
            {Object.entries(TARGETS).map(([k, v]) => (
              <SelectItem key={k} value={k}>
                {v}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <ActionsTable key={target} targetType={target === 'all' ? undefined : target} />
    </>
  )
}
