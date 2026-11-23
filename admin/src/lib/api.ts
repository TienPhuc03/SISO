import axios, { AxiosError } from 'axios'

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000'
const TOKEN_KEY = 'siso-admin-token'

export const tokenStore = {
  get: () => {
    try {
      return localStorage.getItem(TOKEN_KEY)
    } catch {
      return null
    }
  },
  set: (t: string | null) => {
    try {
      if (t) localStorage.setItem(TOKEN_KEY, t)
      else localStorage.removeItem(TOKEN_KEY)
    } catch {
      /* bỏ qua */
    }
  },
}

export const http = axios.create({ baseURL: `${API_BASE_URL}/api/v1` })

http.interceptors.request.use((config) => {
  const token = tokenStore.get()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

/** Phiên hết hạn: xoá token, AuthProvider sẽ đưa về /login. */
export const onUnauthorized = new EventTarget()
http.interceptors.response.use(undefined, (error: AxiosError) => {
  if (error.response?.status === 401) {
    tokenStore.set(null)
    onUnauthorized.dispatchEvent(new Event('logout'))
  }
  return Promise.reject(error)
})

/** Body chuẩn của backend: { success, message, data }. */
export async function get<T>(url: string, params?: object): Promise<T> {
  return (await http.get(url, { params: clean(params) })).data.data
}
export async function send<T>(method: 'post' | 'patch' | 'put' | 'delete', url: string, body?: unknown): Promise<T> {
  return (await http.request({ method, url, data: body })).data.data
}

/** Bỏ tham số rỗng để không gửi `?type=` (backend whitelist sẽ báo lỗi kiểu). */
function clean(params?: object) {
  if (!params) return undefined
  return Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined && v !== '' && v !== null))
}

/**
 * Backend có API admin chưa: route admin không token trả 401 ở bản mới, 404 ở bản cũ (chưa build lại / chưa khởi động lại).
 */
export async function checkBackend(): Promise<'ok' | 'outdated' | 'offline'> {
  try {
    const r = await http.get('/admin/universities', { validateStatus: () => true })
    return r.status === 404 ? 'outdated' : 'ok'
  } catch {
    return 'offline'
  }
}

export function errorMessage(e: unknown): string {
  if (e instanceof AxiosError) {
    const body = e.response?.data as { code?: string; message?: string | string[] } | undefined
    if (body?.message) return Array.isArray(body.message) ? body.message.join(', ') : body.message
    if (!e.response) return 'Không kết nối được máy chủ.'
  }
  return 'Đã có lỗi xảy ra.'
}

export function errorCode(e: unknown): string | undefined {
  return e instanceof AxiosError ? (e.response?.data as { code?: string } | undefined)?.code : undefined
}
