import { useEffect, useState } from 'react'
import { io, type Socket } from 'socket.io-client'
import { API_BASE_URL } from './api'

export interface HexClaimedEvent {
  universityId: string
  universityCode: string
  hexColor: string
  claimedHexes: string[]
  arenaId: string | null
  claimedAt: string
}

/** Kết nối namespace /turf-ws của TurfGateway; gọi `onClaim` mỗi khi có Trường chiếm đất. */
export function useTurfSocket(onClaim: (e: HexClaimedEvent) => void) {
  const [connected, setConnected] = useState(false)
  useEffect(() => {
    const socket: Socket = io(`${API_BASE_URL}/turf-ws`, { transports: ['websocket'] })
    socket.on('connect', () => setConnected(true))
    socket.on('disconnect', () => setConnected(false))
    socket.on('hex_claimed', onClaim)
    return () => {
      socket.disconnect()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return connected
}
