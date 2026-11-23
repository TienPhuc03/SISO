import { useQuery } from '@tanstack/react-query'
import { get } from '@/lib/api'
import type { University } from '@/lib/types'

export const useUniversities = () =>
  useQuery({ queryKey: ['universities'], queryFn: () => get<University[]>('/admin/universities'), staleTime: 5 * 60_000 })

/** Khoá query bị ảnh hưởng khi duyệt / khoá: làm mới cùng lúc. */
export const MODERATION_KEYS = [['gigo-logs'], ['offenders'], ['session'], ['students'], ['actions']]
