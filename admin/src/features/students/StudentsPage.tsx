import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Search, ShieldCheck } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { DataTable } from '@/components/DataTable'
import { BanBadge, Pill, UniversityTag } from '@/components/status'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { get } from '@/lib/api'
import { fmtDateTime, fmtNumber } from '@/lib/format'
import type { Page } from '@/lib/types'
import { useUniversities } from '@/features/anti-cheat/api'

export interface Student {
  id: string
  email: string
  displayName: string
  role: 'user' | 'admin'
  bannedUntil: string | null
  personalKm: number
  createdAt: string
  universityId: string | null
  universityCode: string | null
  universityColor: string | null
  sessions: number
  violations: number
  lastRunAt: string | null
  hasAvatar: boolean
}

const ALL = 'all'
const PAGE_SIZE = 20

export function StudentsPage() {
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const { data: universities } = useUniversities()
  const [text, setText] = useState(params.get('q') ?? '')
  const f = { q: params.get('q') ?? '', uni: params.get('uni') ?? '', status: params.get('status') ?? '', page: Number(params.get('page') ?? 1) }

  const setFilter = (key: string, value: string) => {
    const next = new URLSearchParams(params)
    if (value && value !== ALL) next.set(key, value)
    else next.delete(key)
    if (key !== 'page') next.delete('page')
    setParams(next, { replace: true })
  }

  // Gõ xong 300 ms mới tìm, tránh gọi API mỗi phím.
  useEffect(() => {
    const t = setTimeout(() => text.trim() !== f.q && setFilter('q', text.trim()), 300)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text])

  const list = useQuery({
    queryKey: ['students', f],
    queryFn: () => get<Page<Student>>('/admin/users', { q: f.q, universityId: f.uni, status: f.status, page: f.page, limit: PAGE_SIZE }),
    placeholderData: keepPreviousData,
  })

  const columns = useMemo<ColumnDef<Student>[]>(
    () => [
      {
        header: 'Sinh viên',
        cell: ({ row }) => (
          <div className="min-w-44">
            <div className="flex flex-wrap items-center gap-2 font-medium">
              {row.original.displayName}
              {row.original.role === 'admin' && <Pill tone="info" icon={ShieldCheck}>Admin</Pill>}
              <BanBadge until={row.original.bannedUntil} />
            </div>
            <div className="text-xs text-muted-foreground">{row.original.email}</div>
          </div>
        ),
      },
      { header: 'Trường', cell: ({ row }) => <UniversityTag code={row.original.universityCode} color={row.original.universityColor} /> },
      { header: 'Km cá nhân', cell: ({ row }) => <span className="tabular-nums">{fmtNumber(row.original.personalKm, 2)}</span> },
      { header: 'Phiên', cell: ({ row }) => <span className="tabular-nums">{row.original.sessions}</span> },
      {
        header: 'Vi phạm',
        cell: ({ row }) => (
          <span className={`tabular-nums ${row.original.violations ? 'font-semibold text-destructive' : ''}`}>{row.original.violations}</span>
        ),
      },
      { header: 'Chạy gần nhất', cell: ({ row }) => <span className="whitespace-nowrap tabular-nums">{fmtDateTime(row.original.lastRunAt)}</span> },
      { header: 'Tham gia', cell: ({ row }) => <span className="whitespace-nowrap tabular-nums">{fmtDateTime(row.original.createdAt)}</span> },
    ],
    [],
  )

  return (
    <>
      <PageHeader title="Sinh viên" description="Tìm theo email hoặc tên; bấm một dòng để xem chi tiết, Lịch sử Phiên chạy, khoá hoặc gỡ ảnh đại diện." />
      <div className="mb-3 grid gap-3 sm:grid-cols-[1fr_12rem_12rem]">
        <div className="space-y-1.5">
          <Label htmlFor="s-q" className="text-xs text-muted-foreground">
            Tìm kiếm
          </Label>
          <div className="relative">
            <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input id="s-q" type="search" className="pl-8" placeholder="Email hoặc tên hiển thị" value={text} onChange={(e) => setText(e.target.value)} />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="s-uni" className="text-xs text-muted-foreground">
            Trường
          </Label>
          <Select value={f.uni || ALL} onValueChange={(v) => setFilter('uni', v)}>
            <SelectTrigger id="s-uni" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>Tất cả</SelectItem>
              {universities?.map((u) => (
                <SelectItem key={u.id} value={u.id}>
                  {u.shortCode}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="s-status" className="text-xs text-muted-foreground">
            Trạng thái
          </Label>
          <Select value={f.status || ALL} onValueChange={(v) => setFilter('status', v)}>
            <SelectTrigger id="s-status" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>Tất cả</SelectItem>
              <SelectItem value="banned">Đang bị khoá</SelectItem>
              <SelectItem value="admin">Admin</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>
      <DataTable
        columns={columns}
        data={list.data?.items}
        loading={list.isLoading}
        page={f.page}
        limit={PAGE_SIZE}
        total={list.data?.total}
        onPage={(p) => setFilter('page', String(p))}
        onRowClick={(s) => navigate(`/students/${s.id}`)}
        empty="Không tìm thấy Sinh viên nào."
      />
    </>
  )
}
