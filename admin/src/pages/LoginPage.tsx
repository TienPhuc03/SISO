import { useState, type FormEvent } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Navigate } from 'react-router-dom'
import { Loader2, ServerCrash, ShieldAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { InputOTP, InputOTPGroup, InputOTPSlot } from '@/components/ui/input-otp'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { API_BASE_URL, checkBackend, errorMessage, send } from '@/lib/api'
import { useAuth } from '@/lib/auth'

export function LoginPage() {
  const { status, me, verifyOtp, logout } = useAuth()
  const [email, setEmail] = useState('')
  const [otp, setOtp] = useState('')
  const [step, setStep] = useState<'email' | 'otp'>('email')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [hint, setHint] = useState<string | null>(null)
  const backend = useQuery({ queryKey: ['backend-check'], queryFn: checkBackend, staleTime: 0 })

  if (status === 'admin') return <Navigate to="/" replace />

  const requestOtp = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const r = await send<{ email: string }>('post', '/auth/edu-login', { email })
      setEmail(r.email)
      setHint(`Đã gửi mã OTP 6 số tới ${r.email}.`)
      setStep('otp')
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const submitOtp = async (e?: FormEvent) => {
    e?.preventDefault()
    if (otp.length !== 6) return
    setBusy(true)
    setError(null)
    try {
      await verifyOtp(email, otp)
    } catch (err) {
      setError(errorMessage(err))
      setOtp('')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="grid min-h-dvh place-items-center bg-muted/40 px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-xl">SISO Admin</CardTitle>
          <CardDescription>Đăng nhập bằng email admin và mã OTP.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {backend.data && backend.data !== 'ok' && (
            <Alert variant="destructive">
              <ServerCrash aria-hidden />
              <AlertTitle>{backend.data === 'offline' ? 'Không kết nối được backend' : 'Backend đang chạy bản cũ'}</AlertTitle>
              <AlertDescription>
                <p>
                  {backend.data === 'offline'
                    ? `Không gọi được ${API_BASE_URL}. Hãy chạy backend (cd backend && npm run start:dev) hoặc sửa VITE_API_BASE_URL trong admin/.env.`
                    : `Backend ở ${API_BASE_URL} chưa có API admin. Hãy tắt tiến trình backend cũ rồi chạy lại: cd backend && npm run start:dev.`}
                </p>
                <Button variant="link" className="h-auto p-0" onClick={() => backend.refetch()}>
                  Kiểm tra lại
                </Button>
              </AlertDescription>
            </Alert>
          )}

          {status === 'forbidden' && (
            <Alert variant="destructive">
              <ShieldAlert aria-hidden />
              <AlertTitle>Không có quyền quản trị</AlertTitle>
              <AlertDescription>
                <p>Tài khoản {me?.email} không phải admin.</p>
                <Button variant="link" className="h-auto p-0" onClick={logout}>
                  Đăng nhập tài khoản khác
                </Button>
              </AlertDescription>
            </Alert>
          )}

          {status !== 'forbidden' && step === 'email' && (
            <form onSubmit={requestOtp} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  autoComplete="email"
                  required
                  placeholder="admin@gmail.com hoặc ten@hutech.edu.vn"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  aria-invalid={!!error}
                  aria-describedby={error ? 'login-error' : undefined}
                />
              </div>
              <Button type="submit" className="w-full" disabled={busy}>
                {busy && <Loader2 className="animate-spin" aria-hidden />}
                Gửi mã OTP
              </Button>
            </form>
          )}

          {status !== 'forbidden' && step === 'otp' && (
            <form onSubmit={submitOtp} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="otp">Mã OTP</Label>
                {hint && <p className="text-sm text-muted-foreground">{hint}</p>}
                <InputOTP
                  id="otp"
                  maxLength={6}
                  value={otp}
                  onChange={setOtp}
                  onComplete={() => submitOtp()}
                  inputMode="numeric"
                  autoFocus
                  aria-describedby={error ? 'login-error' : undefined}
                >
                  <InputOTPGroup>
                    {Array.from({ length: 6 }, (_, i) => (
                      <InputOTPSlot key={i} index={i} />
                    ))}
                  </InputOTPGroup>
                </InputOTP>
              </div>
              <div className="flex gap-2">
                <Button type="button" variant="outline" onClick={() => setStep('email')} disabled={busy}>
                  Đổi email
                </Button>
                <Button type="submit" className="flex-1" disabled={busy || otp.length !== 6}>
                  {busy && <Loader2 className="animate-spin" aria-hidden />}
                  Đăng nhập
                </Button>
              </div>
            </form>
          )}

          {error && (
            <p id="login-error" role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
        </CardContent>
      </Card>
    </main>
  )
}
