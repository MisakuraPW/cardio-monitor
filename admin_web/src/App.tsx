import { useEffect, useMemo, useState } from 'react'

import { api } from './api'
import type { AdminOverview, AdminSessionItem, AlertRecord, DeviceRecord, SessionDetail } from './types'

type TabKey = 'overview' | 'devices' | 'sessions' | 'reports' | 'jobs' | 'alerts'

export default function App() {
  const [tab, setTab] = useState<TabKey>('overview')
  const [overview, setOverview] = useState<AdminOverview | null>(null)
  const [devices, setDevices] = useState<DeviceRecord[]>([])
  const [sessions, setSessions] = useState<AdminSessionItem[]>([])
  const [alerts, setAlerts] = useState<AlertRecord[]>([])
  const [selectedSessionId, setSelectedSessionId] = useState<string>('')
  const [sessionDetail, setSessionDetail] = useState<SessionDetail | null>(null)
  const [error, setError] = useState<string>('')

  useEffect(() => {
    void loadDashboard()
  }, [])

  useEffect(() => {
    if (!selectedSessionId) {
      setSessionDetail(null)
      return
    }
    api.getSessionDetail(selectedSessionId).then(setSessionDetail).catch((err: Error) => setError(err.message))
  }, [selectedSessionId])

  async function loadDashboard() {
    try {
      setError('')
      const [nextOverview, nextDevices, nextSessions, nextAlerts] = await Promise.all([
        api.getOverview(),
        api.getDevices(),
        api.getSessions(),
        api.getAlerts(),
      ])
      setOverview(nextOverview)
      setDevices(nextDevices)
      setSessions(nextSessions)
      setAlerts(nextAlerts)
      if (!selectedSessionId && nextSessions[0]) {
        setSelectedSessionId(nextSessions[0].session.id)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'unknown error')
    }
  }

  const reportSessions = useMemo(() => sessions.filter((item) => item.hasReport), [sessions])
  const jobSessions = useMemo(() => sessions.filter((item) => item.latestJob), [sessions])

  return (
    <div className="app-shell">
      <aside className="side-nav">
        <h1>Cardio Cloud Admin</h1>
        <p>面向服务器数据管理、任务跟踪、报告查看与运维联调的后台控制台。</p>
        {([
          ['overview', '总览'],
          ['devices', '设备'],
          ['sessions', '会话'],
          ['reports', '报告'],
          ['jobs', '任务'],
          ['alerts', '告警'],
        ] as Array<[TabKey, string]>).map(([key, label]) => (
          <button key={key} className={tab === key ? 'active' : ''} onClick={() => setTab(key)}>
            {label}
          </button>
        ))}
        <button onClick={() => void loadDashboard()}>刷新数据</button>
      </aside>
      <main className="content">
        {error ? <p className="error">{error}</p> : null}
        {tab === 'overview' && overview ? <OverviewPage overview={overview} /> : null}
        {tab === 'devices' ? <DevicesPage devices={devices} /> : null}
        {tab === 'sessions' ? <SessionsPage sessions={sessions} sessionDetail={sessionDetail} onSelect={setSelectedSessionId} selectedSessionId={selectedSessionId} /> : null}
        {tab === 'reports' ? <ReportsPage sessions={reportSessions} sessionDetail={sessionDetail} onSelect={setSelectedSessionId} selectedSessionId={selectedSessionId} /> : null}
        {tab === 'jobs' ? <JobsPage sessions={jobSessions} /> : null}
        {tab === 'alerts' ? <AlertsPage alerts={alerts} /> : null}
      </main>
    </div>
  )
}

function OverviewPage({ overview }: { overview: AdminOverview }) {
  const metrics = [
    ['设备数', overview.deviceCount],
    ['会话数', overview.sessionCount],
    ['上传数', overview.uploadCount],
    ['分析任务', overview.analysisJobCount],
    ['报告数', overview.reportCount],
    ['原始分块', overview.rawChunkCount],
  ]

  return (
    <>
      <div className="grid">
        {metrics.map(([label, value]) => (
          <section className="card" key={label}>
            <div>{label}</div>
            <div className="metric-value">{value}</div>
          </section>
        ))}
      </div>
      <section className="card" style={{ marginTop: 16 }}>
        <h2>最近会话</h2>
        <table className="table">
          <thead>
            <tr>
              <th>会话 ID</th>
              <th>设备</th>
              <th>模式</th>
              <th>更新时间</th>
            </tr>
          </thead>
          <tbody>
            {overview.latestSessions.map((item) => (
              <tr key={item.id}>
                <td>{item.id}</td>
                <td>{item.deviceId}</td>
                <td>{item.sourceMode}</td>
                <td>{item.updatedAt}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  )
}

function DevicesPage({ devices }: { devices: DeviceRecord[] }) {
  return (
    <section className="card">
      <h2>设备列表</h2>
      <table className="table">
        <thead>
          <tr>
            <th>设备 ID</th>
            <th>来源</th>
            <th>最近状态</th>
            <th>最近心跳</th>
          </tr>
        </thead>
        <tbody>
          {devices.map((item) => (
            <tr key={item.deviceId}>
              <td>{item.deviceId}</td>
              <td>{item.sourceMode}</td>
              <td><span className="pill">{item.lastStatus}</span></td>
              <td>{item.lastSeenAt}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

function SessionsPage({ sessions, sessionDetail, onSelect, selectedSessionId }: { sessions: AdminSessionItem[]; sessionDetail: SessionDetail | null; onSelect: (id: string) => void; selectedSessionId: string }) {
  return (
    <div className="detail-grid">
      <section className="card">
        <h2>会话列表</h2>
        <table className="table">
          <thead>
            <tr>
              <th>设备</th>
              <th>模式</th>
              <th>报告</th>
            </tr>
          </thead>
          <tbody>
            {sessions.map((item) => (
              <tr key={item.session.id} onClick={() => onSelect(item.session.id)} style={{ cursor: 'pointer', background: selectedSessionId === item.session.id ? '#f6fbf8' : undefined }}>
                <td>{item.session.deviceId}</td>
                <td>{item.session.sourceMode}</td>
                <td>{item.hasReport ? '已生成' : '未生成'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
      <section className="card">
        <h2>会话详情</h2>
        {sessionDetail ? (
          <>
            <p className="notice">当前查看会话 {sessionDetail.session.id}</p>
            <p>通道: {sessionDetail.session.channelKeys.join(', ') || '无'}</p>
            <p>上传记录: {sessionDetail.uploads.length}，任务数: {sessionDetail.jobs.length}，原始分块: {sessionDetail.rawChunks.length}</p>
            {sessionDetail.report ? (
              <>
                <h3>最新报告</h3>
                <p>{sessionDetail.report.summary}</p>
              </>
            ) : null}
          </>
        ) : (
          <p className="notice">请选择一个会话查看详情。</p>
        )}
      </section>
    </div>
  )
}

function ReportsPage({ sessions, sessionDetail, onSelect, selectedSessionId }: { sessions: AdminSessionItem[]; sessionDetail: SessionDetail | null; onSelect: (id: string) => void; selectedSessionId: string }) {
  return (
    <div className="detail-grid">
      <section className="card">
        <h2>报告会话</h2>
        <table className="table">
          <thead>
            <tr>
              <th>会话</th>
              <th>设备</th>
            </tr>
          </thead>
          <tbody>
            {sessions.map((item) => (
              <tr key={item.session.id} onClick={() => onSelect(item.session.id)} style={{ cursor: 'pointer', background: selectedSessionId === item.session.id ? '#f6fbf8' : undefined }}>
                <td>{item.session.id}</td>
                <td>{item.session.deviceId}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
      <section className="card">
        <h2>报告内容</h2>
        {sessionDetail?.report ? (
          <>
            <p>{sessionDetail.report.summary}</p>
            <p>置信度: {sessionDetail.report.confidence ?? '未提供'}</p>
            <h3>建议</h3>
            <ul>
              {sessionDetail.report.recommendations.map((item) => <li key={item}>{item}</li>)}
            </ul>
          </>
        ) : (
          <p className="notice">当前会话暂无报告，或尚未选择会话。</p>
        )}
      </section>
    </div>
  )
}

function JobsPage({ sessions }: { sessions: AdminSessionItem[] }) {
  return (
    <section className="card">
      <h2>分析任务</h2>
      <table className="table">
        <thead>
          <tr>
            <th>会话</th>
            <th>状态</th>
            <th>摘要</th>
          </tr>
        </thead>
        <tbody>
          {sessions.map((item) => (
            <tr key={item.session.id}>
              <td>{item.session.id}</td>
              <td>{item.latestJob?.status ?? '-'}</td>
              <td>{item.latestJob?.summary ?? '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

function AlertsPage({ alerts }: { alerts: AlertRecord[] }) {
  return (
    <section className="card">
      <h2>告警列表</h2>
      <table className="table">
        <thead>
          <tr>
            <th>时间</th>
            <th>设备</th>
            <th>级别</th>
            <th>内容</th>
          </tr>
        </thead>
        <tbody>
          {alerts.map((item) => (
            <tr key={item.id}>
              <td>{item.createdAt}</td>
              <td>{item.deviceId}</td>
              <td>{item.severity}</td>
              <td>{item.message}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}
