import { Ban, CheckCircle2, CircleDot, Clock, ShieldX, ShieldQuestion, XCircle, type LucideIcon } from 'lucide-react'
import type { ReviewStatus, RunStatus } from '@/lib/types'
import { cn } from '@/lib/utils'
import { fmtDateTime, isBannedNow, isPermanentBan } from '@/lib/format'

type Tone = 'ok' | 'danger' | 'warn' | 'info' | 'muted'

const TONE: Record<Tone, string> = {
  ok: 'border-ok/30 bg-ok/10 text-ok',
  danger: 'border-destructive/30 bg-destructive/10 text-destructive',
  warn: 'border-warn/30 bg-warn/10 text-warn',
  info: 'border-info/30 bg-info/10 text-info',
  muted: 'border-border bg-muted text-muted-foreground',
}

/** Nhãn trạng thái: luôn có icon + chữ, không chỉ dựa vào màu. */
export function Pill({ tone, icon: Icon, children, title }: { tone: Tone; icon: LucideIcon; children: React.ReactNode; title?: string }) {
  return (
    <span
      title={title}
      className={cn('inline-flex items-center gap-1 whitespace-nowrap rounded-md border px-1.5 py-0.5 text-xs font-medium', TONE[tone])}
    >
      <Icon className="size-3.5 shrink-0" aria-hidden />
      {children}
    </span>
  )
}

const REVIEW: Record<ReviewStatus, [Tone, LucideIcon, string]> = {
  pending: ['warn', Clock, 'Chờ duyệt'],
  confirmed_cheat: ['danger', ShieldX, 'Gian lận'],
  false_positive: ['info', ShieldQuestion, 'Báo nhầm'],
}
export const REVIEW_LABEL: Record<ReviewStatus, string> = {
  pending: 'Chờ duyệt',
  confirmed_cheat: 'Gian lận',
  false_positive: 'Báo nhầm',
}

export function ReviewBadge({ status }: { status: ReviewStatus }) {
  const [tone, icon, label] = REVIEW[status]
  return <Pill tone={tone} icon={icon}>{label}</Pill>
}

const RUN: Record<RunStatus, [Tone, LucideIcon, string]> = {
  COMPLETED: ['ok', CheckCircle2, 'Hợp lệ'],
  REJECTED: ['danger', XCircle, 'Bị loại'],
  ACTIVE: ['info', CircleDot, 'Đang chạy'],
}

export function RunBadge({ status }: { status: RunStatus | null }) {
  if (!status) return <Pill tone="muted" icon={CircleDot}>Không có Phiên</Pill>
  const [tone, icon, label] = RUN[status]
  return <Pill tone={tone} icon={icon}>{label}</Pill>
}

export function BanBadge({ until }: { until: string | null }) {
  if (!isBannedNow(until)) return null
  return (
    <Pill tone="danger" icon={Ban} title={isPermanentBan(until) ? 'Khoá vĩnh viễn' : `Khoá đến ${fmtDateTime(until)}`}>
      {isPermanentBan(until) ? 'Khoá vĩnh viễn' : 'Đang khoá'}
    </Pill>
  )
}

/** Mã Trường kèm chấm màu `hex_color`. */
export function UniversityTag({ code, color }: { code: string | null; color: string | null }) {
  if (!code) return <span className="text-muted-foreground">—</span>
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap text-sm font-medium">
      <span className="size-2.5 shrink-0 rounded-full ring-1 ring-black/10" style={{ background: color ?? undefined }} aria-hidden />
      {code}
    </span>
  )
}
