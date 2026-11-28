import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { cn } from '@/lib/utils'

/** Ô chỉ số: nhãn, số lớn, dòng phụ. Có `to` thì cả ô là link. */
export function StatTile({
  label,
  value,
  sub,
  to,
  tone,
}: {
  label: string
  value: ReactNode
  sub?: ReactNode
  to?: string
  tone?: 'warn' | 'danger'
}) {
  const body = (
    <>
      <div className="text-xs font-medium text-muted-foreground">{label}</div>
      <div className={cn('mt-1 text-2xl font-semibold tabular-nums', tone === 'warn' && 'text-warn', tone === 'danger' && 'text-destructive')}>
        {value}
      </div>
      {sub && <div className="mt-0.5 text-xs text-muted-foreground">{sub}</div>}
    </>
  )
  const cls = 'block rounded-lg border bg-card px-4 py-3'
  return to ? (
    <Link to={to} className={cn(cls, 'transition-colors hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring')}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  )
}
