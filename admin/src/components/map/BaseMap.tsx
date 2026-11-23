import { useEffect, useRef } from 'react'
import * as maplibregl from 'maplibre-gl'
import type { Map as MlMap } from 'maplibre-gl'
// MapLibre v6 tự tìm worker theo import.meta.url, gãy sau khi Vite gom deps: để Vite bundle worker và trỏ thẳng tới nó.
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url'
import { useTheme } from '@/lib/theme'
import { cn } from '@/lib/utils'

maplibregl.setWorkerUrl(workerUrl)

/** Khu thi đấu Bình Thạnh (trung tâm mặc định). */
export const BINH_THANH: [number, number] = [106.7105, 10.8045]

// Tile OSM chuẩn như app (không cần key); tối thì giảm sáng ngay trên lớp raster.
const STYLE: maplibregl.StyleSpecification = {
  version: 8,
  sources: {
    osm: {
      type: 'raster',
      tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      tileSize: 256,
      maxzoom: 19,
      attribution: '© OpenStreetMap contributors',
    },
  },
  layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
}

/**
 * Bản đồ MapLibre nền OSM. `onReady` chạy một lần khi style đã tải xong; component cha thêm source/layer của mình.
 */
export function BaseMap({
  onReady,
  className,
  center = BINH_THANH,
  zoom = 14,
  label,
}: {
  onReady: (map: MlMap) => void
  className?: string
  center?: [number, number]
  zoom?: number
  label: string
}) {
  const el = useRef<HTMLDivElement>(null)
  const mapRef = useRef<MlMap | null>(null)
  const { resolved } = useTheme()
  const ready = useRef(onReady)
  ready.current = onReady

  useEffect(() => {
    const map = new maplibregl.Map({ container: el.current!, style: STYLE, center, zoom, attributionControl: { compact: true } })
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right')
    map.on('load', () => ready.current(map))
    mapRef.current = map
    return () => map.remove()
    // Tạo bản đồ một lần; thay đổi dữ liệu do component cha cập nhật source.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    const apply = () => {
      const dark = resolved === 'dark'
      map.setPaintProperty('osm', 'raster-saturation', dark ? -0.8 : -0.4)
      map.setPaintProperty('osm', 'raster-brightness-max', dark ? 0.45 : 1)
      map.setPaintProperty('osm', 'raster-contrast', dark ? 0.1 : 0)
    }
    if (map.isStyleLoaded()) apply()
    else map.once('load', apply)
  }, [resolved])

  return <div ref={el} role="region" aria-label={label} className={cn('overflow-hidden rounded-lg border', className)} />
}
