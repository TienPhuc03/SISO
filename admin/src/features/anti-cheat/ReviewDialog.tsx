import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { REVIEW_LABEL } from '@/components/status'
import { errorMessage, send } from '@/lib/api'
import { fmtNumber, rejectionLabel } from '@/lib/format'
import type { GigoLog, ReviewStatus } from '@/lib/types'
import { MODERATION_KEYS } from './api'

export function ReviewDialog({ log, onClose }: { log: GigoLog | null; onClose: () => void }) {
  return (
    <Dialog open={!!log} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>{log && <ReviewForm key={log.id} log={log} onClose={onClose} />}</DialogContent>
    </Dialog>
  )
}

function ReviewForm({ log, onClose }: { log: GigoLog; onClose: () => void }) {
  const qc = useQueryClient()
  const [status, setStatus] = useState<ReviewStatus>(log.reviewStatus === 'pending' ? 'confirmed_cheat' : log.reviewStatus)
  const [restore, setRestore] = useState(false)
  const canRestore = status === 'false_positive' && log.sessionStatus === 'REJECTED'

  const mutation = useMutation({
    mutationFn: () =>
      send<{ restored: { addedKm: number; inCurrentSeason: boolean } | null }>('patch', `/admin/gigo-logs/${log.id}/review`, {
        status,
        ...(canRestore && restore && { restoreSession: true }),
      }),
    onSuccess: (r) => {
      MODERATION_KEYS.forEach((k) => qc.invalidateQueries({ queryKey: k }))
      if (r.restored)
        toast.success(
          r.restored.inCurrentSeason
            ? `Đã khôi phục Phiên chạy, cộng bù ${fmtNumber(r.restored.addedKm, 2)} km.`
            : 'Đã khôi phục Phiên chạy (thuộc Mùa giải trước nên không cộng km).',
        )
      else toast.success(`Đã lưu kết luận: ${REVIEW_LABEL[status]}.`)
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <>
      <DialogHeader>
        <DialogTitle>Kết luận vi phạm</DialogTitle>
        <DialogDescription>
          {log.displayName} · {log.rejectionType} ({rejectionLabel(log.rejectionType)})
        </DialogDescription>
      </DialogHeader>
      <div className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="review-status">Kết luận</Label>
          <Select value={status} onValueChange={(v) => setStatus(v as ReviewStatus)}>
            <SelectTrigger id="review-status" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="confirmed_cheat">Gian lận (xác nhận)</SelectItem>
              <SelectItem value="false_positive">Báo nhầm</SelectItem>
              <SelectItem value="pending">Chờ duyệt</SelectItem>
            </SelectContent>
          </Select>
        </div>
        {canRestore && (
          <div className="flex items-start gap-3 rounded-md border p-3">
            <Switch id="restore" checked={restore} onCheckedChange={setRestore} />
            <div className="space-y-1">
              <Label htmlFor="restore">Khôi phục Phiên chạy</Label>
              <p className="text-sm text-muted-foreground">
                Phiên thành hợp lệ và cộng bù {fmtNumber((log.sessionDistanceMeters ?? 0) / 1000, 2)} km cho Sinh viên và
                Trường nếu thuộc Mùa giải đang mở. Đất không được chiếm bù.
              </p>
            </div>
          </div>
        )}
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onClose}>
          Huỷ
        </Button>
        <Button onClick={() => mutation.mutate()} disabled={mutation.isPending}>
          {mutation.isPending && <Loader2 className="animate-spin" aria-hidden />}
          Lưu kết luận
        </Button>
      </DialogFooter>
    </>
  )
}
