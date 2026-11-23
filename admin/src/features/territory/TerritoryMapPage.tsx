import { useEffect, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import * as maplibregl from 'maplibre-gl'
import type { GeoJSONSource, Map as MlMap } from 'maplibre-gl'
import { RefreshCw } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { BaseMap } from '@/components/map/BaseMap'
import { StatTile } from '@/components/StatTile'
import { UniversityTag } from '@/components/status'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { get } from '@/lib/api'
import { fmtDateTime, fmtNumber } from '@/lib/format'
import { useTurfSocket, type HexClaimedEvent } from '@/lib/socket'
import { useTheme } from '@/lib/theme'
import { useUniversities } from '@/features/anti-cheat/api'
import { hexFeatures, hoursToNeutral, type Arena, type Hex } from './territory'

const ALL = 'all'
const RISK_OPTIONS = [6, 12, 24]
const WARN = { light: '#c2410c', dark: '#fbbf24' }

export function TerritoryMapPage() {
  const qc = useQueryClient()
  const { resolved } = useTheme()
  const [arenaId, setArenaId] = useState(ALL)
  const [riskHours, setRiskHours] = useState(6)
  const [feed, setFeed] = useState<HexClaimedEvent[]>([])
  const mapRef = useRef<MlMap | null>(null)
  const [mapReady, setMapReady] = useState(false)
  const { data: universities } = useUniversities()

  const arenas = useQuery({ queryKey: ['arenas-public'], queryFn: () => get<Arena[]>('/turf/arenas') })
  const hexes = useQuery({
    queryKey: ['hexagons', arenaId],
    queryFn: () => get<Hex[]>('/turf/hexagons', { arenaId: arenaId === ALL ? undefined : arenaId }),
    // Hao mòn do pg_cron chạy, không có sự kiện socket: làm mới định kỳ.
    refetchInterval: 5 * 60_000,
  })

  const connected = useTurfSocket((e) => {
    setFeed((f) => [e, ...f].slice(0, 8))
    qc.invalidateQueries({ queryKey: ['hexagons'] })
  })

  // turf/hexagons không lọc Đấu trường đã tắt; chỉ giữ ô của Đấu trường đang hoạt động.
  const data = useMemo(() => {
    const active = new Set(arenas.data?.map((a) => a.id))
    return (hexes.data ?? []).filter((h) => h.arenaId && active.has(h.arenaId))
  }, [hexes.data, arenas.data])
  const features = useMemo(() => hexFeatures(data, riskHours), [data, riskHours])

  // Thống kê theo Trường trong phạm vi đang xem.
  const rows = useMemo(() => {
    const by = new Map<string, { code: string; color: string; count: number; hp: number; atRisk: number }>()
    for (const h of data) {
      if (!h.ownerUniversityId) continue
      const r = by.get(h.ownerUniversityId) ?? { code: h.universityCode ?? '?', color: h.hexColor.slice(0, 7), count: 0, hp: 0, atRisk: 0 }
      r.count++
      r.hp += h.shieldHp
      if (hoursToNeutral(h) <= riskHours) r.atRisk++
      by.set(h.ownerUniversityId, r)
    }
    return [...by.values()].sort((a, b) => b.count - a.count)
  }, [data, riskHours])
  const owned = rows.reduce((s, r) => s + r.count, 0)
  const atRisk = rows.reduce((s, r) => s + r.atRisk, 0)

  const onReady = (map: MlMap) => {
    map.addSource('arenas', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
    map.addLayer({ id: 'arena-line', type: 'line', source: 'arenas', paint: { 'line-color': '#64748b', 'line-width': 2, 'line-dasharray': [3, 2] } })
    map.addSource('hexes', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
    map.addLayer({
      id: 'hex-fill',
      type: 'fill',
      source: 'hexes',
      paint: {
        'fill-color': ['get', 'color'],
        // Độ đậm theo Độ bền: 100 HP đậm, càng hao mòn càng nhạt; ô Trung lập gần trong suốt.
        'fill-opacity': ['case', ['get', 'owned'], ['+', 0.18, ['*', 0.5, ['/', ['get', 'hp'], 100]]], 0.06],
      },
    })
    map.addLayer({ id: 'hex-line', type: 'line', source: 'hexes', paint: { 'line-color': ['get', 'color'], 'line-width': 0.8, 'line-opacity': 0.7 } })
    map.addLayer({
      id: 'hex-risk',
      type: 'line',
      source: 'hexes',
      filter: ['==', ['get', 'atRisk'], true],
      paint: { 'line-color': WARN.light, 'line-width': 3, 'line-dasharray': [1.5, 1] },
    })
    map.on('click', 'hex-fill', (e) => {
      const p = e.features?.[0]?.properties
      if (!p) return
      new maplibregl.Popup({ closeButton: true }).setLngLat(e.lngLat).setDOMContent(hexPopup(p)).addTo(map)
    })
    map.on('mouseenter', 'hex-fill', () => (map.getCanvas().style.cursor = 'pointer'))
    map.on('mouseleave', 'hex-fill', () => (map.getCanvas().style.cursor = ''))
    mapRef.current = map
    setMapReady(true)
  }

  useEffect(() => {
    if (!mapReady) return
    ;(mapRef.current!.getSource('hexes') as GeoJSONSource).setData(features)
  }, [features, mapReady])

  useEffect(() => {
    if (!mapReady) return
    mapRef.current!.setPaintProperty('hex-risk', 'line-color', WARN[resolved])
  }, [resolved, mapReady])

  // Ranh giới Đấu trường + căn khung theo Đấu trường đang chọn.
  useEffect(() => {
    if (!mapReady || !arenas.data) return
    const map = mapRef.current!
    const shown = arenas.data.filter((a) => a.boundary && (arenaId === ALL || a.id === arenaId))
    ;(map.getSource('arenas') as GeoJSONSource).setData({
      type: 'FeatureCollection',
      features: shown.map((a) => ({ type: 'Feature', properties: { name: a.name }, geometry: a.boundary! })),
    })
    const pts = shown.flatMap((a) => a.boundary!.coordinates[0]) as [number, number][]
    if (pts.length) {
      const b = pts.reduce((acc, p) => acc.extend(p), new maplibregl.LngLatBounds(pts[0], pts[0]))
      map.fitBounds(b, { padding: 40, maxZoom: 17, duration: 400 })
    }
  }, [arenas.data, arenaId, mapReady])

  const uniCode = (id: string) => universities?.find((u) => u.id === id)

  return (
    <>
      <PageHeader
        title="Bản đồ Lãnh thổ"
        description="Ô đất tô theo Trường đang giữ; càng nhạt là Độ bền càng thấp. Viền cam nét đứt: sắp về Trung lập."
        actions={
          <span className="inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm" role="status">
            <span className={`size-2 rounded-full ${connected ? 'bg-ok' : 'bg-muted-foreground'}`} aria-hidden />
            {connected ? 'Realtime đang kết nối' : 'Realtime mất kết nối'}
          </span>
        }
      />

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div className="w-full space-y-1.5 sm:w-72">
          <Label htmlFor="arena" className="text-xs text-muted-foreground">
            Đấu trường
          </Label>
          <Select value={arenaId} onValueChange={setArenaId}>
            <SelectTrigger id="arena" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>Tất cả Đấu trường đang hoạt động</SelectItem>
              {arenas.data?.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name} ({a.hexCount} ô)
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="w-44 space-y-1.5">
          <Label htmlFor="risk" className="text-xs text-muted-foreground">
            Sắp về Trung lập trong
          </Label>
          <Select value={String(riskHours)} onValueChange={(v) => setRiskHours(Number(v))}>
            <SelectTrigger id="risk" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {RISK_OPTIONS.map((h) => (
                <SelectItem key={h} value={String(h)}>
                  ≤ {h} giờ
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <Button variant="outline" onClick={() => hexes.refetch()} disabled={hexes.isFetching}>
          <RefreshCw className={hexes.isFetching ? 'animate-spin' : undefined} aria-hidden /> Làm mới
        </Button>
        <span className="text-xs text-muted-foreground">Cập nhật {fmtDateTime(hexes.dataUpdatedAt ? new Date(hexes.dataUpdatedAt).toISOString() : null)}</span>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatTile label="Tổng số ô" value={data.length} />
        <StatTile label="Ô có chủ" value={owned} sub={data.length ? `${fmtNumber((owned / data.length) * 100)}%` : undefined} />
        <StatTile label="Ô Trung lập" value={data.length - owned} />
        <StatTile label={`Sắp về Trung lập (≤ ${riskHours} giờ)`} value={atRisk} tone={atRisk ? 'warn' : undefined} />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <BaseMap onReady={onReady} className="h-[460px] lg:h-[600px]" label="Bản đồ Ô đất H3 theo Trường" />
          <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground" aria-label="Chú giải bản đồ">
            {universities?.map((u) => (
              <li key={u.id} className="flex items-center gap-1.5">
                <span className="size-3 rounded-sm" style={{ background: u.hexColor }} aria-hidden /> {u.shortCode}
              </li>
            ))}
            <li className="flex items-center gap-1.5">
              <span className="size-3 rounded-sm border border-slate-400 bg-slate-400/10" aria-hidden /> Trung lập
            </li>
            <li className="flex items-center gap-1.5">
              <span className="size-3 rounded-sm border-2 border-dashed" style={{ borderColor: WARN[resolved] }} aria-hidden /> Sắp về Trung lập
            </li>
            <li className="flex items-center gap-1.5">
              <span className="h-0 w-4 border-t-2 border-dashed border-slate-500" aria-hidden /> Ranh giới Đấu trường
            </li>
          </ul>
        </div>

        <div className="space-y-4">
          <Card className="gap-3 py-4">
            <CardHeader className="px-4">
              <CardTitle className="text-base">Lãnh thổ theo Trường</CardTitle>
            </CardHeader>
            <CardContent className="px-4">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Trường</TableHead>
                    <TableHead className="text-right">Ô</TableHead>
                    <TableHead className="text-right">Độ bền TB</TableHead>
                    <TableHead className="text-right">Sắp mất</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody className="tabular-nums">
                  {rows.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={4} className="h-16 text-center text-muted-foreground">
                        Chưa Trường nào giữ Ô đất ở đây.
                      </TableCell>
                    </TableRow>
                  )}
                  {rows.map((r) => (
                    <TableRow key={r.code}>
                      <TableCell>
                        <UniversityTag code={r.code} color={r.color} />
                      </TableCell>
                      <TableCell className="text-right">{r.count}</TableCell>
                      <TableCell className="text-right">{fmtNumber(r.hp / r.count, 0)}</TableCell>
                      <TableCell className={`text-right ${r.atRisk ? 'font-semibold text-warn' : ''}`}>{r.atRisk}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <Card className="gap-3 py-4">
            <CardHeader className="px-4">
              <CardTitle className="text-base">Chiếm đất gần đây</CardTitle>
            </CardHeader>
            <CardContent className="px-4">
              {feed.length === 0 ? (
                <p className="text-sm text-muted-foreground">Chưa có sự kiện nào từ khi mở trang.</p>
              ) : (
                <ul className="space-y-2 text-sm" aria-live="polite">
                  {feed.map((e, i) => (
                    <li key={i} className="flex items-center justify-between gap-2">
                      <span className="flex items-center gap-2">
                        <UniversityTag code={e.universityCode} color={uniCode(e.universityId)?.hexColor ?? e.hexColor} />
                        chiếm {e.claimedHexes.length} ô
                      </span>
                      <span className="tabular-nums text-xs text-muted-foreground">{fmtDateTime(e.claimedAt)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  )
}

/** Nội dung popup dựng bằng DOM (textContent) để không chèn HTML từ dữ liệu. */
function hexPopup(p: Record<string, unknown>) {
  const el = document.createElement('div')
  el.className = 'space-y-0.5 text-xs text-slate-900'
  const line = (text: string, bold = false) => {
    const d = document.createElement('div')
    d.textContent = text
    if (bold) d.style.fontWeight = '600'
    el.appendChild(d)
  }
  if (p.owned) {
    const left = 48 - (Date.now() - new Date(String(p.patrolled)).getTime()) / 3_600_000
    line(`${p.code} · Độ bền ${p.hp}`, true)
    line(`Tuần tra lần cuối: ${fmtDateTime(String(p.patrolled))}`)
    line(left > 0 ? `Còn ~${fmtNumber(left)} giờ trước khi về Trung lập` : 'Đã quá hạn, chờ cron Hao mòn')
  } else {
    line('Ô Trung lập', true)
  }
  line(String(p.h3))
  return el
}
