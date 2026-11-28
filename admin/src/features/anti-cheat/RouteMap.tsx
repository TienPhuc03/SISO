import { useEffect, useRef } from 'react'
import * as maplibregl from 'maplibre-gl'
import type { GeoJSONSource, Map as MlMap } from 'maplibre-gl'
import { BaseMap } from '@/components/map/BaseMap'
import { useTheme } from '@/lib/theme'
import type { SessionWindow } from '@/lib/types'

// MapLibre không đọc oklch: dùng hex tương đương token --ok / --warn cho từng theme.
const COLORS = {
  light: { ok: '#15803d', warn: '#c2410c', halo: '#ffffff' },
  dark: { ok: '#34d399', warn: '#fbbf24', halo: '#0f172a' },
}

/** Mỗi cửa sổ là một đoạn, nối từ điểm cuối cửa sổ trước để Đường chạy liền mạch. */
function toGeoJson(windows: SessionWindow[]): GeoJSON.FeatureCollection {
  const features: GeoJSON.Feature[] = []
  let prev: [number, number] | null = null
  for (const w of windows) {
    if (!w.points.length) continue
    const coords = prev ? [prev, ...w.points] : w.points
    if (coords.length >= 2)
      features.push({ type: 'Feature', properties: { passed: w.passed, seq: w.seq }, geometry: { type: 'LineString', coordinates: coords } })
    prev = w.points[w.points.length - 1]
  }
  const all = windows.flatMap((w) => w.points)
  if (all.length) {
    features.push({ type: 'Feature', properties: { kind: 'start' }, geometry: { type: 'Point', coordinates: all[0] } })
    features.push({ type: 'Feature', properties: { kind: 'end' }, geometry: { type: 'Point', coordinates: all[all.length - 1] } })
  }
  return { type: 'FeatureCollection', features }
}

export function RouteMap({ windows }: { windows: SessionWindow[] }) {
  const mapRef = useRef<MlMap | null>(null)
  const { resolved } = useTheme()
  const c = COLORS[resolved]

  const paint = (map: MlMap) => {
    const col = COLORS[resolved]
    map.setPaintProperty('route', 'line-color', ['case', ['get', 'passed'], col.ok, col.warn])
    map.setPaintProperty('route-halo', 'line-color', col.halo)
    map.setPaintProperty('ends', 'circle-stroke-color', col.halo)
  }

  const onReady = (map: MlMap) => {
    mapRef.current = map
    const data = toGeoJson(windows)
    map.addSource('route', { type: 'geojson', data })
    map.addLayer({ id: 'route-halo', type: 'line', source: 'route', filter: ['==', '$type', 'LineString'], paint: { 'line-width': 7, 'line-color': c.halo }, layout: { 'line-cap': 'round', 'line-join': 'round' } })
    map.addLayer({
      id: 'route',
      type: 'line',
      source: 'route',
      filter: ['==', '$type', 'LineString'],
      paint: { 'line-width': 4, 'line-color': ['case', ['get', 'passed'], c.ok, c.warn], 'line-dasharray': ['case', ['get', 'passed'], ['literal', [1, 0]], ['literal', [2, 1]]] },
      layout: { 'line-cap': 'round', 'line-join': 'round' },
    })
    map.addLayer({
      id: 'ends',
      type: 'circle',
      source: 'route',
      filter: ['==', '$type', 'Point'],
      paint: { 'circle-radius': 6, 'circle-color': ['match', ['get', 'kind'], 'start', '#2563eb', '#475569'], 'circle-stroke-width': 2, 'circle-stroke-color': c.halo },
    })
    const all = windows.flatMap((w) => w.points)
    if (all.length) {
      const b = all.reduce((acc, p) => acc.extend(p), new maplibregl.LngLatBounds(all[0], all[0]))
      map.fitBounds(b, { padding: 48, maxZoom: 18, duration: 0 })
    }
  }

  useEffect(() => {
    const map = mapRef.current
    if (map?.getLayer('route')) paint(map)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resolved])

  useEffect(() => {
    ;(mapRef.current?.getSource('route') as GeoJSONSource | undefined)?.setData(toGeoJson(windows))
  }, [windows])

  const hasPoints = windows.some((w) => w.points.length)
  return (
    <div>
      <div className="relative">
        <BaseMap onReady={onReady} className="h-80 lg:h-[420px]" label="Bản đồ Đường chạy theo cửa sổ" />
        {!hasPoints && (
          <div className="absolute inset-0 grid place-items-center rounded-lg bg-background/70 text-sm text-muted-foreground">
            Phiên chạy không có điểm GPS nào.
          </div>
        )}
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground" aria-label="Chú giải bản đồ">
        <li className="flex items-center gap-1.5">
          <span className="inline-block h-1 w-5 rounded" style={{ background: c.ok }} aria-hidden /> Cửa sổ đạt
        </li>
        <li className="flex items-center gap-1.5">
          <span className="inline-block h-1 w-5 rounded border-t-2 border-dashed" style={{ borderColor: c.warn }} aria-hidden /> Cửa sổ nghi
          ngờ (nét đứt)
        </li>
        <li className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-full bg-[#2563eb]" aria-hidden /> Bắt đầu
        </li>
        <li className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-full bg-[#475569]" aria-hidden /> Kết thúc
        </li>
      </ul>
    </div>
  )
}
