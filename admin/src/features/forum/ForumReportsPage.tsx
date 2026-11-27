import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Check, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { PageHeader } from '@/components/PageHeader'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { errorMessage, get, send } from '@/lib/api'
import { fmtDateTime } from '@/lib/format'

interface ForumReport {
  id: string
  reason: string | null
  createdAt: string
  resolvedAt: string | null
  reporterEmail: string
  postId: string
  postBody: string
  postImages: string[]
  postAuthorEmail: string
  commentId: string | null
  commentBody: string | null
  commentAuthorEmail: string | null
  reportCount: number
}

/** Báo cáo của Sinh viên về bài đăng / bình luận diễn đàn: bỏ qua hoặc xoá nội dung. */
export function ForumReportsPage() {
  const qc = useQueryClient()
  const [status, setStatus] = useState<'open' | 'all'>('open')
  const reports = useQuery({ queryKey: ['forum-reports', status], queryFn: () => get<ForumReport[]>('/admin/forum/reports', { status }) })

  const run = (fn: () => Promise<unknown>, ok: string) =>
    fn()
      .then(() => {
        qc.invalidateQueries({ queryKey: ['forum-reports'] })
        qc.invalidateQueries({ queryKey: ['actions'] })
        toast.success(ok)
      })
      .catch((e) => {
        toast.error(errorMessage(e))
        throw e
      })

  const columns = useMemo<ColumnDef<ForumReport>[]>(
    () => [
      { header: 'Lúc', cell: ({ row }) => <span className="whitespace-nowrap text-xs tabular-nums">{fmtDateTime(row.original.createdAt)}</span> },
      {
        header: 'Nội dung bị báo cáo',
        cell: ({ row }) => {
          const r = row.original
          return (
            <div className="min-w-64 max-w-md space-y-1">
              <div className="text-xs text-muted-foreground">
                {r.commentId ? `Bình luận của ${r.commentAuthorEmail}` : `Bài của ${r.postAuthorEmail}`} · {r.reportCount} báo cáo
              </div>
              <p className="line-clamp-3 whitespace-pre-wrap">{r.commentId ? r.commentBody : r.postBody || '(chỉ có ảnh)'}</p>
              {!r.commentId && r.postImages.length > 0 && (
                <div className="flex gap-1">
                  {r.postImages.map((src) => (
                    <a key={src} href={src} target="_blank" rel="noreferrer">
                      <img src={src} alt="Ảnh trong bài" className="size-14 rounded object-cover" loading="lazy" />
                    </a>
                  ))}
                </div>
              )}
            </div>
          )
        },
      },
      {
        header: 'Lý do / Người báo cáo',
        cell: ({ row }) => (
          <div className="min-w-40 text-xs">
            <div>{row.original.reason ?? '—'}</div>
            <div className="text-muted-foreground">{row.original.reporterEmail}</div>
          </div>
        ),
      },
      {
        header: 'Trạng thái',
        cell: ({ row }) => (
          <span className="text-xs">{row.original.resolvedAt ? `Đã xử lý ${fmtDateTime(row.original.resolvedAt)}` : 'Đang mở'}</span>
        ),
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Thao tác</span>,
        cell: ({ row }) => {
          const r = row.original
          const what = r.commentId ? 'bình luận' : 'bài đăng'
          return (
            <div className="flex justify-end gap-1">
              {!r.resolvedAt && (
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Bỏ qua báo cáo"
                  title="Bỏ qua (không vi phạm)"
                  onClick={() => run(() => send('post', `/admin/forum/reports/${r.id}/dismiss`), 'Đã bỏ qua báo cáo.').catch(() => {})}
                >
                  <Check />
                </Button>
              )}
              <ConfirmDialog
                title={`Xoá ${what}?`}
                description={
                  r.commentId
                    ? 'Bình luận bị xoá hẳn, mọi báo cáo về nó cũng mất.'
                    : 'Bài bị xoá hẳn cùng ảnh, tym, bình luận và mọi báo cáo về bài. Không hoàn tác được.'
                }
                confirmLabel={`Xoá ${what}`}
                onConfirm={() =>
                  run(
                    () => send('delete', r.commentId ? `/admin/forum/comments/${r.commentId}` : `/admin/forum/posts/${r.postId}`),
                    `Đã xoá ${what}.`,
                  )
                }
                trigger={
                  <Button variant="ghost" size="icon" aria-label={`Xoá ${what}`}>
                    <Trash2 />
                  </Button>
                }
              />
            </div>
          )
        },
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  return (
    <>
      <PageHeader title="Diễn đàn" description="Báo cáo của Sinh viên về bài đăng và bình luận. Xoá nội dung vi phạm hoặc bỏ qua báo cáo." />
      <Tabs value={status} onValueChange={(v) => setStatus(v as 'open' | 'all')} className="mb-3">
        <TabsList>
          <TabsTrigger value="open">Đang mở</TabsTrigger>
          <TabsTrigger value="all">Tất cả</TabsTrigger>
        </TabsList>
      </Tabs>
      <DataTable columns={columns} data={reports.data} loading={reports.isLoading} empty="Không có báo cáo nào." />
    </>
  )
}
