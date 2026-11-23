import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { get, onUnauthorized, send, tokenStore } from './api'

export interface Me {
  id: string
  email: string
  displayName: string
  role: 'user' | 'admin'
  /** null = admin dùng email ngoài trường. */
  university: { id: string; shortCode: string; name: string; color: string } | null
}

type Status = 'loading' | 'anonymous' | 'forbidden' | 'admin'

const AuthContext = createContext<{
  status: Status
  me: Me | null
  verifyOtp: (email: string, otp: string) => Promise<void>
  logout: () => void
}>(null!)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null)
  const [status, setStatus] = useState<Status>(tokenStore.get() ? 'loading' : 'anonymous')

  const accept = useCallback((token: string, user: Me) => {
    tokenStore.set(token)
    setMe(user)
    setStatus(user.role === 'admin' ? 'admin' : 'forbidden')
  }, [])

  const logout = useCallback(() => {
    tokenStore.set(null)
    setMe(null)
    setStatus('anonymous')
  }, [])

  useEffect(() => {
    if (!tokenStore.get()) return
    get<{ accessToken: string; user: Me }>('/auth/me')
      .then((r) => accept(r.accessToken, r.user))
      .catch(logout)
  }, [accept, logout])

  useEffect(() => {
    const handler = () => logout()
    onUnauthorized.addEventListener('logout', handler)
    return () => onUnauthorized.removeEventListener('logout', handler)
  }, [logout])

  const verifyOtp = async (email: string, otp: string) => {
    const r = await send<{ accessToken: string; user: Me }>('post', '/auth/verify-otp', { email, otp })
    accept(r.accessToken, r.user)
  }

  return <AuthContext.Provider value={{ status, me, verifyOtp, logout }}>{children}</AuthContext.Provider>
}

export const useAuth = () => useContext(AuthContext)
