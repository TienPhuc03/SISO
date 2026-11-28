import { cellToBoundary } from 'h3-js'

/** GIỮ KHỚP backend: NEUTRAL_AFTER_HOURS (notifications) và private.decay_hexagons() (24 giờ còn 50 HP, 48 giờ về Trung lập). */
export const NEUTRAL_AFTER_HOURS = 48

export interface Hex {
  h3Index: string
  arenaId: string | null
  ownerUniversityId: string | null
  universityCode: string | null
  hexColor: string
  shieldHp: number
  lastPatrolledAt: string
}

export interface Arena {
  id: string
  name: string
  description: string | null
  hexCount: number
  boundary: { type: 'Polygon'; coordinates: number[][][] } | null
}

/** Số giờ còn lại trước khi Ô đất có chủ về Trung lập (âm = quá hạn, cron sắp xử lý). */
export const hoursToNeutral = (hex: Hex, now = Date.now()) =>
  NEUTRAL_AFTER_HOURS - (now - new Date(hex.lastPatrolledAt).getTime()) / 3_600_000

export function hexFeatures(hexes: Hex[], atRiskHours: number, now = Date.now()): GeoJSON.FeatureCollection {
  return {
    type: 'FeatureCollection',
    features: hexes.map((h) => {
      const owned = !!h.ownerUniversityId
      const left = owned ? hoursToNeutral(h, now) : null
      return {
        type: 'Feature',
        id: h.h3Index,
        properties: {
          h3: h.h3Index,
          owned,
          color: owned ? h.hexColor.slice(0, 7) : '#94a3b8',
          hp: h.shieldHp,
          code: h.universityCode ?? '',
          patrolled: h.lastPatrolledAt,
          atRisk: owned && left! <= atRiskHours,
        },
        geometry: { type: 'Polygon', coordinates: [cellToBoundary(h.h3Index, true)] },
      }
    }),
  }
}
