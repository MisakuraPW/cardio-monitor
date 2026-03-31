export type SessionRecord = {
  id: string
  deviceId: string
  sourceMode: string
  channelKeys: string[]
  startedAt: string
  updatedAt: string
}

export type UploadRecord = {
  id: string
  sessionId: string
  status: string
  createdAt: string
  lastMessage: string
}

export type AnalysisJobRecord = {
  id: string
  sessionId: string
  status: string
  createdAt: string
  completedAt?: string | null
  summary: string
}

export type AdminSessionItem = {
  session: SessionRecord
  latestUpload?: UploadRecord | null
  latestJob?: AnalysisJobRecord | null
  hasReport: boolean
  rawChunkCount: number
}

export type DeviceRecord = {
  deviceId: string
  sourceMode: string
  lastSeenAt: string
  lastStatus: string
  metadata: Record<string, unknown>
}

export type AlertRecord = {
  id: string
  sessionId: string
  deviceId: string
  severity: string
  message: string
  createdAt: string
  payload: Record<string, unknown>
}

export type AdminOverview = {
  deviceCount: number
  sessionCount: number
  uploadCount: number
  analysisJobCount: number
  reportCount: number
  rawChunkCount: number
  alertCount: number
  latestSessions: SessionRecord[]
}

export type SessionDetail = {
  session: SessionRecord
  uploads: UploadRecord[]
  jobs: AnalysisJobRecord[]
  report?: {
    summary: string
    confidence?: number | null
    recommendations: string[]
  } | null
  rawChunks: Array<{ id: string; channelKey: string; sourceType: string; sampleCount: number; objectKey: string }>
  alerts: AlertRecord[]
}
