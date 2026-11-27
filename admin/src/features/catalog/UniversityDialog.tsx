import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { errorMessage, send } from '@/lib/api'
import type { University } from '@/lib/types'
import { useUniversityCatalog } from '@/features/anti-cheat/api'

const HEX = /^#[0-9A-Fa-f]{6}$/
const DOMAIN = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/
const UNI_KEYS = [['universities'], ['scores'], ['seasons']]

export function UniversityDialog({ university, trigger }: { university?: University; trigger: React.ReactNode }) {
  const qc = useQueryClient()
  const catalog = useUniversityCatalog()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({
    shortCode: university?.shortCode ?? '',
    shortName: university?.shortName ?? '',
    name: university?.name ?? '',
    district: university?.district ?? '',
    parentName: university?.parentName ?? '',
    aliases: university?.aliases ?? '',
    emailDomain: university?.emailDomain ?? '',
    hexColor: university?.hexColor ?? '#2563EB',
  })
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [k]: e.target.value })
  const errors: Partial<Record<keyof typeof form, string | null>> = {
    shortCode: form.shortCode.trim().length < 2 ? 'Tối thiểu 2 ký tự.' : null,
    name: form.name.trim().length < 2 ? 'Tối thiểu 2 ký tự.' : null,
    district: form.district ? null : 'Chọn quận.',
    emailDomain: !form.emailDomain.trim() || DOMAIN.test(form.emailDomain.trim()) ? null : 'Tên miền chữ thường, ví dụ hutech.edu.vn.',
    hexColor: HEX.test(form.hexColor) ? null : 'Dạng #RRGGBB.',
  }
  const invalid = Object.values(errors).some(Boolean)
  const clusterOf = (district: string) => {
    const code = catalog.data?.districts.find((d) => d.name === district)?.clusterCode
    return catalog.data?.clusters.find((c) => c.code === code)?.name
  }

  const save = useMutation({
    mutationFn: () => {
      // Ô trống gửi undefined: backend lưu null (DTO không nhận chuỗi rỗng cho tên miền)
      const body = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v.trim() || undefined]))
      return university ? send('patch', `/admin/universities/${university.id}`, body) : send('post', '/admin/universities', body)
    },
    onSuccess: () => {
      UNI_KEYS.forEach((k) => qc.invalidateQueries({ queryKey: k }))
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
          <DialogTitle>{university ? `Sửa ${university.shortName}` : 'Thêm Trường'}</DialogTitle>
          <DialogDescription>Mỗi Trường là một cơ sở thi đấu. Quận quyết định Cụm của Trường trên Bảng xếp hạng.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          {field('shortCode', 'Mã trường (duy nhất)', { maxLength: 20 })}
          {field('shortName', 'Tên ngắn hiển thị', { maxLength: 20, placeholder: 'Bỏ trống = mã trường' })}
          <div className="sm:col-span-2">{field('name', 'Tên trường đầy đủ', { maxLength: 100 })}</div>
          <div className="space-y-1.5">
            <Label htmlFor="u-district">Quận</Label>
            <Select value={form.district} onValueChange={(v) => setForm({ ...form, district: v })}>
              <SelectTrigger id="u-district" className="w-full" aria-invalid={!!errors.district}>
                <SelectValue placeholder="Chọn quận" />
              </SelectTrigger>
              <SelectContent>
                {catalog.data?.districts.map((d) => (
                  <SelectItem key={d.name} value={d.name}>
                    {d.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">{form.district ? clusterOf(form.district) : errors.district}</p>
          </div>
          {field('parentName', 'Thương hiệu chung', { maxLength: 60, placeholder: 'vd. UEH' })}
          <div className="sm:col-span-2">{field('aliases', 'Từ khoá tìm thêm (không dấu)', { maxLength: 300, placeholder: 'vd. kinh te ueh' })}</div>
          {field('emailDomain', 'Đuôi email (tham khảo)', { maxLength: 50, placeholder: 'hutech.edu.vn' })}
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

/** Gộp Trường trùng (thường do Sinh viên tự thêm) vào một Trường khác. */
export function MergeUniversityDialog({
  university,
  universities,
  trigger,
}: {
  university: University
  universities: University[]
  trigger: React.ReactNode
}) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [targetId, setTargetId] = useState('')
  const target = universities.find((u) => u.id === targetId)

  const merge = useMutation({
    mutationFn: () => send('post', `/admin/universities/${university.id}/merge`, { targetId }),
    onSuccess: () => {
      UNI_KEYS.forEach((k) => qc.invalidateQueries({ queryKey: k }))
      toast.success(`Đã gộp ${university.shortName} vào ${target?.shortName}.`)
      setOpen(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Gộp {university.shortName}</DialogTitle>
          <DialogDescription>
            {university.studentCount} Sinh viên, Ô đất, Quỹ Km và Quán quân của “{university.name}” chuyển sang Trường được chọn, rồi Trường này bị xoá. Không hoàn tác
            được.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="merge-target">Gộp vào</Label>
          <Select value={targetId} onValueChange={setTargetId}>
            <SelectTrigger id="merge-target" className="w-full">
              <SelectValue placeholder="Chọn Trường giữ lại" />
            </SelectTrigger>
            <SelectContent>
              {universities
                .filter((u) => u.id !== university.id)
                .map((u) => (
                  <SelectItem key={u.id} value={u.id}>
                    {u.shortName} · {u.name}
                  </SelectItem>
                ))}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Huỷ
          </Button>
          <Button variant="destructive" onClick={() => merge.mutate()} disabled={!targetId || merge.isPending}>
            {merge.isPending && <Loader2 className="animate-spin" aria-hidden />}
            Gộp Trường
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
