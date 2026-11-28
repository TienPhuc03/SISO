// Tự kiểm tra nhanh (chạy: npx tsx src/features/territory/territory.test.ts): logic Ô đất sắp về Trung lập.
import assert from 'node:assert/strict'
import { hexFeatures, hoursToNeutral, type Hex } from './territory'

const NOW = Date.parse('2026-11-23T12:00:00Z')
const hex = (hoursAgo: number, owner: string | null = 'u1'): Hex => ({
  h3Index: '8a65b56718b7fff',
  arenaId: 'a',
  ownerUniversityId: owner,
  universityCode: owner ? 'UEF' : null,
  hexColor: owner ? '#ED1C24' : '#44FFFFFF',
  shieldHp: 100,
  lastPatrolledAt: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
})

assert.equal(hoursToNeutral(hex(0), NOW), 48)
assert.equal(hoursToNeutral(hex(43), NOW), 5)
const fc = hexFeatures([hex(43), hex(41), hex(47, null)], 6, NOW)
assert.deepEqual(
  fc.features.map((f) => f.properties!.atRisk),
  [true, false, false], // còn 5 giờ: sắp về Trung lập; còn 7 giờ: chưa; ô Trung lập không bao giờ "sắp về Trung lập"
)
assert.equal(fc.features[2].properties!.color, '#94a3b8')
assert.equal((fc.features[0].geometry as GeoJSON.Polygon).coordinates[0].length, 7) // lục giác khép kín
console.log('territory.test: OK')
