import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { errorMessage, send } from '@/lib/api'

export interface SeasonRow {
  seasonNumber: number
  startDate: string
  endDate: string
  isActive: boolean
  /** Quán quân mỗi Cụm (rỗng nếu Mùa chưa đóng / không có hoạt động) */
  champions: { clusterCode: string | null; id: string; code: string; color: string; powerPct: number }[]
}

/** Tạo (season = undefined) hoặc sửa một Mùa giải. */
export function SeasonDialog({ season, trigger }: { season?: SeasonRow; trigger: React.ReactNode }) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [start, setStart] = useState(season?.startDate ?? '')
  const [end, setEnd] = useState(season?.endDate ?? '')
  const [active, setActive] = useState(season?.isActive ?? false)
  const invalid = !start || !end || start > end

  const save = useMutation({
    mutationFn: () =>
      season
        ? send('patch', `/admin/seasons/${season.seasonNumber}`, { startDate: start, endDate: end, ...(active !== season.isActive && { isActive: active }) })
        : send('post', '/admin/seasons', { startDate: start, endDate: end, isActive: active }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['seasons'] })
      toast.success(season ? `Đã cập nhật Mùa giải ${season.seasonNumber}.` : 'Đã tạo Mùa giải.')
      setOpen(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{season ? `Sửa Mùa giải ${season.seasonNumber}` : 'Tạo Mùa giải'}</DialogTitle>
          <DialogDescription>
            Cron đóng Mùa giải đang mở vào 00:00 sau ngày kết thúc, ghi Quán quân và tự mở Mùa giải mới đến hết tháng.
          </DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="s-start">Ngày bắt đầu</Label>
            <Input id="s-start" type="date" value={start} max={end || undefined} onChange={(e) => setStart(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="s-end">Ngày kết thúc</Label>
            <Input id="s-end" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
          </div>
        </div>
        <div className="flex items-start gap-3 rounded-md border p-3">
          <Switch id="s-active" checked={active} onCheckedChange={setActive} disabled={season?.isActive} />
          <div className="space-y-1">
            <Label htmlFor="s-active">Đang mở</Label>
            <p className="text-sm text-muted-foreground">
              {season?.isActive
                ? 'Mùa giải này đang mở; để đóng, hãy mở một Mùa giải khác.'
                : 'Bật thì Mùa giải đang mở hiện tại bị tắt cờ (chỉ một Mùa giải mở cùng lúc).'}
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Huỷ
          </Button>
          <Button onClick={() => save.mutate()} disabled={invalid || save.isPending}>
            {save.isPending && <Loader2 className="animate-spin" aria-hidden />}
            Lưu
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
