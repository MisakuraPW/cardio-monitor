import type { AdminOverview, AdminSessionItem, AlertRecord, DeviceRecord, SessionDetail } from './types'

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8000'
const ADMIN_TOKEN = import.meta.env.VITE_ADMIN_TOKEN ?? 'change-me'

async function requestJson<T>(path: string): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: {
      'X-Admin-Token': ADMIN_TOKEN,
    },
  })
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`)
  }
  return (await response.json()) as T
}

export const api = {
  getOverview: () => requestJson<AdminOverview>('/api/v1/admin/overview'),
  getSessions: () => requestJson<AdminSessionItem[]>('/api/v1/admin/sessions'),
  getSessionDetail: (sessionId: string) => requestJson<SessionDetail>(`/api/v1/admin/sessions/${sessionId}`),
  getDevices: () => requestJson<DeviceRecord[]>('/api/v1/admin/devices'),
  getAlerts: () => requestJson<AlertRecord[]>('/api/v1/admin/alerts'),
}
