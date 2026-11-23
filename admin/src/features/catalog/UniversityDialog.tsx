import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { errorMessage, send } from '@/lib/api'
import type { University } from '@/lib/types'

const HEX = /^#[0-9A-Fa-f]{6}$/
const DOMAIN = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/

export function UniversityDialog({ university, trigger }: { university?: University; trigger: React.ReactNode }) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({
    shortCode: university?.shortCode ?? '',
    name: university?.name ?? '',
    emailDomain: university?.emailDomain ?? '',
    hexColor: university?.hexColor ?? '#2563EB',
  })
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [k]: e.target.value })
  const errors = {
    shortCode: form.shortCode.trim().length < 2 ? 'Tối thiểu 2 ký tự.' : null,
    name: form.name.trim().length < 2 ? 'Tối thiểu 2 ký tự.' : null,
    emailDomain: DOMAIN.test(form.emailDomain.trim()) ? null : 'Tên miền chữ thường, ví dụ hutech.edu.vn.',
    hexColor: HEX.test(form.hexColor) ? null : 'Dạng #RRGGBB.',
  }
  const invalid = Object.values(errors).some(Boolean)

  const save = useMutation({
    mutationFn: () => (university ? send('patch', `/admin/universities/${university.id}`, form) : send('post', '/admin/universities', form)),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['universities'] })
      toast.success(university ? 'Đã cập nhật Trường.' : 'Đã thêm Trường.')
      setOpen(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const field = (k: keyof typeof form, label: string, props: React.ComponentProps<typeof Input> = {}) => (
    <div className="space-y-1.5">
      <Label htmlFor={`u-${k}`}>{label}</Label>
      <Input id={`u-${k}`} value={form[k]} onChange={set(k)} aria-invalid={!!errors[k]} aria-describedby={`u-${k}-err`} {...props} />
      {errors[k] && (
        <p id={`u-${k}-err`} className="text-xs text-destructive">
          {errors[k]}
        </p>
      )}
    </div>
  )

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{university ? `Sửa ${university.shortCode}` : 'Thêm Trường'}</DialogTitle>
          <DialogDescription>
            Đuôi email có hiệu lực đăng nhập ngay ở backend (subdomain tự được chấp nhận). App Flutter còn kiểm tra theo danh sách cũ, nên Trường mới
            cần cập nhật app.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          {field('shortCode', 'Mã trường', { maxLength: 20 })}
          {field('emailDomain', 'Đuôi email', { maxLength: 50, placeholder: 'hutech.edu.vn' })}
          <div className="sm:col-span-2">{field('name', 'Tên trường', { maxLength: 100 })}</div>
          <div className="space-y-1.5">
            <Label htmlFor="u-color-picker">Màu Trường</Label>
            <div className="flex gap-2">
              <input
                id="u-color-picker"
                type="color"
                value={HEX.test(form.hexColor) ? form.hexColor : '#000000'}
                onChange={(e) => setForm({ ...form, hexColor: e.target.value.toUpperCase() })}
                className="h-9 w-12 cursor-pointer rounded-md border bg-transparent p-1"
                aria-label="Chọn màu"
              />
              <Input value={form.hexColor} onChange={set('hexColor')} maxLength={7} aria-label="Mã màu hex" aria-invalid={!!errors.hexColor} className="font-mono" />
            </div>
            {errors.hexColor && <p className="text-xs text-destructive">{errors.hexColor}</p>}
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
