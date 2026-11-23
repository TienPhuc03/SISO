import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Ban, Loader2, LockOpen } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { errorMessage, send } from '@/lib/api'
import { isBannedNow } from '@/lib/format'
import { MODERATION_KEYS } from './api'

const DURATIONS: Record<string, string> = { '1': '1 ngày', '7': '7 ngày', '30': '30 ngày', permanent: 'Vĩnh viễn' }

/** Nút Khoá / Gỡ khoá cho một Sinh viên, tuỳ trạng thái hiện tại. */
export function BanButton({
  user,
  size = 'sm',
}: {
  user: { id: string; email: string; bannedUntil: string | null }
  size?: 'sm' | 'default'
}) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [duration, setDuration] = useState('7')
  const [reason, setReason] = useState('')
  const refresh = () => MODERATION_KEYS.forEach((k) => qc.invalidateQueries({ queryKey: k }))

  const ban = useMutation({
    mutationFn: () =>
      send<{ rejectedSessions: number }>('post', `/admin/users/${user.id}/ban`, {
        reason: reason.trim(),
        ...(duration !== 'permanent' && { until: new Date(Date.now() + +duration * 86_400_000).toISOString() }),
      }),
    onSuccess: (r) => {
      refresh()
      toast.success(
        `Đã khoá ${user.email}` + (r.rejectedSessions ? `, loại ${r.rejectedSessions} Phiên đang chạy.` : '.'),
      )
      setOpen(false)
      setReason('')
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const unban = useMutation({
    mutationFn: () => send('delete', `/admin/users/${user.id}/ban`),
    onSuccess: () => {
      refresh()
      toast.success(`Đã gỡ khoá ${user.email}.`)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  if (isBannedNow(user.bannedUntil))
    return (
      <Button variant="outline" size={size} onClick={(e) => (e.stopPropagation(), unban.mutate())} disabled={unban.isPending}>
        {unban.isPending ? <Loader2 className="animate-spin" aria-hidden /> : <LockOpen aria-hidden />}
        Gỡ khoá
      </Button>
    )

  const reasonOk = reason.trim().length >= 3
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="destructive" size={size} onClick={(e) => e.stopPropagation()}>
          <Ban aria-hidden /> Khoá
        </Button>
      </DialogTrigger>
      <DialogContent onClick={(e) => e.stopPropagation()}>
        <DialogHeader>
          <DialogTitle>Khoá Sinh viên</DialogTitle>
          <DialogDescription>
            {user.email} sẽ không gửi được Phiên chạy mới; các Phiên đang chạy bị loại ngay.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="ban-duration">Thời hạn</Label>
            <Select value={duration} onValueChange={setDuration}>
              <SelectTrigger id="ban-duration" className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(DURATIONS).map(([v, l]) => (
                  <SelectItem key={v} value={v}>
                    {l}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="ban-reason">Lý do</Label>
            <Textarea
              id="ban-reason"
              value={reason}
              maxLength={200}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Ví dụ: Đi xe máy nhiều lần (ERR_202)"
              aria-describedby="ban-reason-help"
            />
            <p id="ban-reason-help" className="text-xs text-muted-foreground">
              Bắt buộc, tối thiểu 3 ký tự. Lưu vào Nhật ký admin.
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Huỷ
          </Button>
          <Button variant="destructive" onClick={() => ban.mutate()} disabled={!reasonOk || ban.isPending}>
            {ban.isPending && <Loader2 className="animate-spin" aria-hidden />}
            Khoá {DURATIONS[duration].toLowerCase()}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
