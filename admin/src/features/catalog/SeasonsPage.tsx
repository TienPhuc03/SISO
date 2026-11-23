import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { CalendarPlus, Crown, Pencil, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { PageHeader } from '@/components/PageHeader'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { StatTile } from '@/components/StatTile'
import { Pill, UniversityTag } from '@/components/status'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { errorMessage, get, send } from '@/lib/api'
import { fmtNumber } from '@/lib/format'
import type { University } from '@/lib/types'
import { useUniversities } from '@/features/anti-cheat/api'
import { SeasonDialog, type SeasonRow } from './SeasonForms'
import { UniversityDialog } from './UniversityDialog'

interface Score {
  university_id: string
  name: string
  short_code: string
  hex_color: string
  total_season_km: number
  territory_pct: string
  mileage_pct: string
  composite_power_pct: string
}
interface ArenaRow {
  id: string
  name: string
  description: string | null
  isActive: boolean
  hexCount: number
  ownedCount: number
}

const fmtDay = (d: string) => d.split('-').reverse().join('/')
const DAY_MS = 86_400_000

export function SeasonsPage() {
  const qc = useQueryClient()
  const seasons = useQuery({ queryKey: ['seasons'], queryFn: () => get<SeasonRow[]>('/admin/seasons') })
  const scores = useQuery({ queryKey: ['scores'], queryFn: () => get<Score[]>('/leaderboard/scores'), refetchInterval: 60_000 })
  const universities = useUniversities()
  const arenas = useQuery({ queryKey: ['admin-arenas'], queryFn: () => get<ArenaRow[]>('/admin/arenas') })

  const run = (fn: () => Promise<unknown>, ok: string, keys: string[][]) =>
    fn()
      .then(() => {
        keys.forEach((k) => qc.invalidateQueries({ queryKey: k }))
        toast.success(ok)
      })
      .catch((e) => {
        toast.error(errorMessage(e))
        throw e
      })

  const toggleArena = useMutation({
    mutationFn: (a: ArenaRow) => send('patch', `/admin/arenas/${a.id}`, { isActive: !a.isActive }),
    onSuccess: (_, a) => {
      qc.invalidateQueries({ queryKey: ['admin-arenas'] })
      qc.invalidateQueries({ queryKey: ['arenas-public'] })
      toast.success(`${a.isActive ? 'Đã tắt' : 'Đã bật'} ${a.name}.`)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const current = seasons.data?.find((s) => s.isActive)
  const progress = useMemo(() => {
    if (!current) return null
    const start = new Date(`${current.startDate}T00:00:00+07:00`).getTime()
    const end = new Date(`${current.endDate}T00:00:00+07:00`).getTime() + DAY_MS
    const pct = Math.min(100, Math.max(0, ((Date.now() - start) / (end - start)) * 100))
    return { pct, daysLeft: Math.max(0, Math.ceil((end - Date.now()) / DAY_MS)), totalDays: Math.round((end - start) / DAY_MS) }
  }, [current])

  const ranked = (scores.data ?? []).map((s) => ({
    ...s,
    territory: Number(s.territory_pct),
    mileage: Number(s.mileage_pct),
    composite: Number(s.composite_power_pct),
  }))
  const maxComposite = Math.max(1, ...ranked.map((r) => r.composite))

  const seasonColumns = useMemo<ColumnDef<SeasonRow>[]>(
    () => [
      { header: 'Mùa', cell: ({ row }) => <span className="font-semibold tabular-nums">{row.original.seasonNumber}</span> },
      { header: 'Bắt đầu', cell: ({ row }) => <span className="tabular-nums">{fmtDay(row.original.startDate)}</span> },
      { header: 'Kết thúc', cell: ({ row }) => <span className="tabular-nums">{fmtDay(row.original.endDate)}</span> },
      {
        header: 'Trạng thái',
        cell: ({ row }) => (row.original.isActive ? <Pill tone="ok" icon={CalendarPlus}>Đang mở</Pill> : <Pill tone="muted" icon={CalendarPlus}>Đã đóng</Pill>),
      },
      {
        header: 'Quán quân',
        cell: ({ row }) =>
          row.original.championCode ? (
            <span className="inline-flex items-center gap-2">
              <UniversityTag code={row.original.championCode} color={row.original.championColor} />
              <span className="text-xs tabular-nums text-muted-foreground">{fmtNumber(row.original.championPowerPct, 2)}%</span>
            </span>
          ) : (
            <span className="text-muted-foreground">—</span>
          ),
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Thao tác</span>,
        cell: ({ row }) => {
          const s = row.original
          return (
            <div className="flex justify-end gap-1">
              <SeasonDialog
                season={s}
                trigger={
                  <Button variant="ghost" size="icon" aria-label={`Sửa Mùa giải ${s.seasonNumber}`}>
                    <Pencil />
                  </Button>
                }
              />
              {!s.isActive && !s.championCode && (
                <ConfirmDialog
                  title={`Xoá Mùa giải ${s.seasonNumber}?`}
                  description="Chỉ xoá được Mùa giải chưa mở và chưa có Quán quân."
                  confirmLabel="Xoá"
                  onConfirm={() => run(() => send('delete', `/admin/seasons/${s.seasonNumber}`), 'Đã xoá Mùa giải.', [['seasons']])}
                  trigger={
                    <Button variant="ghost" size="icon" aria-label={`Xoá Mùa giải ${s.seasonNumber}`}>
                      <Trash2 />
                    </Button>
                  }
                />
              )}
            </div>
          )
        },
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  const uniColumns = useMemo<ColumnDef<University>[]>(
    () => [
      { header: 'Trường', cell: ({ row }) => <UniversityTag code={row.original.shortCode} color={row.original.hexColor} /> },
      { header: 'Tên', cell: ({ row }) => row.original.name },
      { header: 'Đuôi email', cell: ({ row }) => <span className="font-mono text-xs">{row.original.emailDomain}</span> },
      { header: 'Màu', cell: ({ row }) => <span className="font-mono text-xs">{row.original.hexColor}</span> },
      {
        id: 'actions',
        header: () => <span className="sr-only">Thao tác</span>,
        cell: ({ row }) => {
          const u = row.original
          return (
            <div className="flex justify-end gap-1">
              <UniversityDialog
                university={u}
                trigger={
                  <Button variant="ghost" size="icon" aria-label={`Sửa ${u.shortCode}`}>
                    <Pencil />
                  </Button>
                }
              />
              <ConfirmDialog
                title={`Xoá ${u.shortCode}?`}
                description="Chỉ xoá được Trường chưa có Sinh viên. Ô đất của Trường (nếu có) về Trung lập."
                confirmLabel="Xoá Trường"
                onConfirm={() => run(() => send('delete', `/admin/universities/${u.id}`), `Đã xoá ${u.shortCode}.`, [['universities'], ['scores']])}
                trigger={
                  <Button variant="ghost" size="icon" aria-label={`Xoá ${u.shortCode}`}>
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

  const arenaColumns = useMemo<ColumnDef<ArenaRow>[]>(
    () => [
      {
        header: 'Đấu trường',
        cell: ({ row }) => (
          <div className="min-w-48">
            <div className="font-medium">{row.original.name}</div>
            {row.original.description && <div className="text-xs text-muted-foreground">{row.original.description}</div>}
          </div>
        ),
      },
      { header: 'Số ô', cell: ({ row }) => <span className="tabular-nums">{row.original.hexCount}</span> },
      { header: 'Ô có chủ', cell: ({ row }) => <span className="tabular-nums">{row.original.ownedCount}</span> },
      {
        header: 'Hoạt động',
        cell: ({ row }) => (
          <div className="flex items-center gap-2">
            <Switch
              checked={row.original.isActive}
              onCheckedChange={() => toggleArena.mutate(row.original)}
              disabled={toggleArena.isPending}
              aria-label={`${row.original.isActive ? 'Tắt' : 'Bật'} ${row.original.name}`}
            />
            <span className="text-sm text-muted-foreground">{row.original.isActive ? 'Đang mở' : 'Đã tắt'}</span>
          </div>
        ),
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [toggleArena.isPending],
  )

  return (
    <>
      <PageHeader title="Mùa giải & Trường" description="Tiến độ Mùa giải, xếp hạng Sức mạnh Tổng hợp và quản lý Mùa giải / Trường / Đấu trường." />

      <div className="mb-6 grid gap-4 xl:grid-cols-3">
        <Card className="gap-3 py-4">
          <CardHeader className="px-4">
            <CardTitle className="text-base">{current ? `Mùa giải ${current.seasonNumber}` : 'Chưa có Mùa giải đang mở'}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 px-4">
            {current && progress && (
              <>
                <p className="text-sm text-muted-foreground tabular-nums">
                  {fmtDay(current.startDate)} – {fmtDay(current.endDate)} · {progress.totalDays} ngày
                </p>
                <div
                  className="h-2 overflow-hidden rounded-full bg-muted"
                  role="progressbar"
                  aria-valuenow={Math.round(progress.pct)}
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-label="Tiến độ Mùa giải"
                >
                  <div className="h-full rounded-full bg-primary" style={{ width: `${progress.pct}%` }} />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <StatTile label="Đã qua" value={`${fmtNumber(progress.pct, 0)}%`} />
                  <StatTile label="Còn lại" value={`${progress.daysLeft} ngày`} />
                </div>
              </>
            )}
          </CardContent>
        </Card>

        <Card className="gap-3 py-4 xl:col-span-2">
          <CardHeader className="px-4">
            <CardTitle className="text-base">Xếp hạng hiện tại</CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto px-4">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-xs uppercase tracking-wide text-muted-foreground">
                  <th className="py-2 pr-2 font-medium">#</th>
                  <th className="py-2 pr-2 font-medium">Trường</th>
                  <th className="py-2 pr-2 text-right font-medium">% Lãnh thổ</th>
                  <th className="py-2 pr-2 text-right font-medium">% Km</th>
                  <th className="py-2 pr-2 text-right font-medium">Quỹ Km</th>
                  <th className="w-1/3 py-2 font-medium">Sức mạnh Tổng hợp</th>
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {ranked.map((r, i) => (
                  <tr key={r.university_id} className="border-b last:border-0">
                    <td className="py-2 pr-2 text-muted-foreground">{i + 1}</td>
                    <td className="py-2 pr-2">
                      <UniversityTag code={r.short_code} color={r.hex_color} />
                    </td>
                    <td className="py-2 pr-2 text-right">{fmtNumber(r.territory, 2)}%</td>
                    <td className="py-2 pr-2 text-right">{fmtNumber(r.mileage, 2)}%</td>
                    <td className="py-2 pr-2 text-right">{fmtNumber(r.total_season_km, 2)} km</td>
                    <td className="py-2">
                      <div className="flex items-center gap-2">
                        <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                          <div className="h-full rounded-full" style={{ width: `${(r.composite / maxComposite) * 100}%`, background: r.hex_color }} />
                        </div>
                        <span className="w-14 text-right font-medium">{fmtNumber(r.composite, 2)}%</span>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="mt-2 text-xs text-muted-foreground">Sức mạnh Tổng hợp = ½ % Lãnh thổ + ½ % Km.</p>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="seasons">
        <TabsList>
          <TabsTrigger value="seasons">Mùa giải & Đại sảnh Danh vọng</TabsTrigger>
          <TabsTrigger value="universities">Trường</TabsTrigger>
          <TabsTrigger value="arenas">Đấu trường</TabsTrigger>
        </TabsList>
        <TabsContent value="seasons" className="mt-4 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
              <Crown className="size-4" aria-hidden /> Quán quân được ghi khi cron đóng Mùa giải.
            </p>
            <SeasonDialog
              trigger={
                <Button>
                  <Plus aria-hidden /> Tạo Mùa giải
                </Button>
              }
            />
          </div>
          <DataTable columns={seasonColumns} data={seasons.data} loading={seasons.isLoading} empty="Chưa có Mùa giải nào." />
        </TabsContent>
        <TabsContent value="universities" className="mt-4 space-y-3">
          <div className="flex justify-end">
            <UniversityDialog
              trigger={
                <Button>
                  <Plus aria-hidden /> Thêm Trường
                </Button>
              }
            />
          </div>
          <DataTable columns={uniColumns} data={universities.data} loading={universities.isLoading} />
        </TabsContent>
        <TabsContent value="arenas" className="mt-4 space-y-3">
          <p className="text-sm text-muted-foreground">
            Tắt một Đấu trường thì nó biến khỏi danh sách Đấu trường của app và không chiếm đất ở đó được nữa. Ranh giới và Ô đất thêm bằng{' '}
            <code className="text-xs">npm run seed:hexagons</code>.
          </p>
          <DataTable columns={arenaColumns} data={arenas.data} loading={arenas.isLoading} />
        </TabsContent>
      </Tabs>
    </>
  )
}
