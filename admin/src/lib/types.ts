export type ReviewStatus = 'pending' | 'confirmed_cheat' | 'false_positive'
export type RunStatus = 'ACTIVE' | 'REJECTED' | 'COMPLETED'

export interface Page<T> {
  items: T[]
  total: number
  page: number
  limit: number
}

export interface University {
  id: string
  shortCode: string
  name: string
  emailDomain: string
  hexColor: string
}

export interface GigoLog {
  id: string
  rejectionType: string
  gpsSpeedMps: number
  cadenceSpm: number
  verticalEnergyG: number | null
  gpsAccuracyM: number | null
  reviewStatus: ReviewStatus
  reviewedAt: string | null
  reviewedByEmail: string | null
  createdAt: string
  sessionId: string | null
  sessionStatus: RunStatus | null
  sessionDistanceMeters: number | null
  userId: string
  email: string
  displayName: string
  bannedUntil: string | null
  universityCode: string | null
  universityColor: string | null
}

export interface Offender {
  userId: string
  email: string
  displayName: string
  bannedUntil: string | null
  universityCode: string | null
  universityColor: string | null
  violations: number
  confirmed: number
  pending: number
  types: string[]
  lastAt: string
}

export interface SessionWindow {
  seq: number
  speedMps: number
  cadenceSpm: number
  passed: boolean
  recordedAt: string
  points: [number, number][]
}

export interface SessionDetail {
  session: {
    sessionId: string
    status: RunStatus
    sessionType: string
    distanceMeters: number
    durationSeconds: number
    hexCount: number
    rejectionReason: string | null
    startedAt: string
    finishedAt: string | null
    windows: SessionWindow[]
  }
  user: {
    id: string
    email: string
    displayName: string
    bannedUntil: string | null
    universityCode: string | null
    universityColor: string | null
  } | null
  auditLogs: GigoLog[]
}
