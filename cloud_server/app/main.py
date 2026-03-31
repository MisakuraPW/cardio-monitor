from __future__ import annotations

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from .analysis_service import process_analysis_job
from .config import settings
from .models import (
    AdminOverview,
    AdminSessionItem,
    AlertCreate,
    AlertRecord,
    AnalysisJobCreate,
    AnalysisJobRecord,
    ChannelCatalogCreate,
    ChannelCatalogRecord,
    DeviceRecord,
    DeviceUpsert,
    FrameBatchIngest,
    IngestSessionOpen,
    MedicalReport,
    RawChunkRecord,
    SessionCreate,
    SessionDetail,
    SessionRecord,
    UploadCreate,
    UploadRecord,
)
from .storage import SQLiteStorage

storage = SQLiteStorage()
app = FastAPI(title='Cardio Cloud Service', version='0.2.0')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.get('/', response_class=HTMLResponse)
def index() -> str:
    return '''
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Cardio Cloud Service</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; background: #f5f8f6; color: #1f2933; }
          .card { background: white; border: 1px solid #d8e2dc; border-radius: 16px; padding: 24px; max-width: 840px; }
          a { color: #0b6e4f; }
          code { background: #f0f4f8; padding: 2px 6px; border-radius: 6px; }
          li { margin-bottom: 8px; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Cardio Cloud Service</h1>
          <p>云端已经启动成功。当前服务包含 API、管理查询接口、MQTT 接入预留和分析 Provider 抽象。</p>
          <ul>
            <li>打开 <a href="/docs" target="_blank">/docs</a> 查看 Swagger 接口文档</li>
            <li>访问 <a href="/api/v1/health" target="_blank">/api/v1/health</a> 检查服务存活</li>
            <li>上位机上传沿用 <code>POST /api/v1/sessions</code> 和 <code>/uploads</code></li>
            <li>设备直传可使用 <code>/api/v1/ingest/mqtt/*</code> 接口或独立 MQTT ingest 服务</li>
          </ul>
          <p>管理后台建议单独运行 <code>admin_web</code>，并通过 <code>X-Admin-Token</code> 访问 admin 接口。</p>
        </div>
      </body>
    </html>
    '''


@app.get('/api/v1/health')
def health() -> dict[str, str]:
    return {
        'status': 'ok',
        'env': settings.app_env,
        'analysisExecutionMode': settings.analysis_execution_mode,
    }


@app.post('/api/v1/sessions', response_model=SessionRecord)
def create_session(payload: SessionCreate) -> SessionRecord:
    return storage.create_session(payload)


@app.get('/api/v1/sessions/{session_id}', response_model=SessionDetail)
def get_session(session_id: str) -> SessionDetail:
    try:
        return storage.get_session_detail(session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail='Session not found') from exc


@app.get('/api/v1/sessions/{session_id}/raw', response_model=list[RawChunkRecord])
def get_session_raw(session_id: str) -> list[RawChunkRecord]:
    if storage.get_session(session_id) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    return storage.list_raw_chunks(session_id)


@app.post('/api/v1/sessions/{session_id}/uploads', response_model=UploadRecord)
def create_upload(session_id: str, payload: UploadCreate) -> UploadRecord:
    if storage.get_session(session_id) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    return storage.create_upload(session_id, payload)


@app.post('/api/v1/analysis/jobs', response_model=AnalysisJobRecord)
def create_analysis_job(payload: AnalysisJobCreate) -> AnalysisJobRecord:
    if storage.get_session(payload.sessionId) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    if storage.get_latest_upload_payload(payload.sessionId) is None:
        raise HTTPException(status_code=400, detail='Upload payload not found')

    job = storage.create_analysis_job(payload)
    if settings.analysis_execution_mode == 'inline':
        process_analysis_job(storage, settings, job.id)
        return storage.get_analysis_job(job.id)
    return job


@app.get('/api/v1/analysis/jobs/{job_id}', response_model=AnalysisJobRecord)
def get_analysis_job(job_id: str) -> AnalysisJobRecord:
    try:
        return storage.get_analysis_job(job_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail='Analysis job not found') from exc


@app.get('/api/v1/reports/{session_id}', response_model=MedicalReport)
def get_report(session_id: str) -> MedicalReport:
    report = storage.get_report(session_id)
    if report is None:
        raise HTTPException(status_code=404, detail='Report not found')
    return report


@app.post('/api/v1/ingest/mqtt/session/open', response_model=SessionRecord)
def open_ingest_session(payload: IngestSessionOpen) -> SessionRecord:
    record = storage.create_session(
        SessionCreate(
            deviceId=payload.deviceId,
            sourceMode=payload.sourceMode,
            channelKeys=payload.channelKeys,
            startedAt=payload.startedAt,
        )
    )
    storage.upsert_device(
        DeviceUpsert(
            deviceId=payload.deviceId,
            sourceMode=payload.sourceMode,
            lastStatus='session_opened',
            metadata=payload.metadata,
        )
    )
    return record


@app.post('/api/v1/ingest/mqtt/catalog', response_model=ChannelCatalogRecord)
def ingest_catalog(payload: ChannelCatalogCreate) -> ChannelCatalogRecord:
    if storage.get_session(payload.sessionId) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    return storage.save_channel_catalog(payload)


@app.post('/api/v1/ingest/mqtt/frame-batch', response_model=RawChunkRecord)
def ingest_frame_batch(payload: FrameBatchIngest) -> RawChunkRecord:
    if storage.get_session(payload.sessionId) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    return storage.ingest_frame_batch(payload)


@app.post('/api/v1/ingest/mqtt/alerts', response_model=AlertRecord)
def ingest_alert(payload: AlertCreate) -> AlertRecord:
    if storage.get_session(payload.sessionId) is None:
        raise HTTPException(status_code=404, detail='Session not found')
    return storage.create_alert(payload)


@app.post('/api/v1/ingest/mqtt/device', response_model=DeviceRecord)
def upsert_device(payload: DeviceUpsert) -> DeviceRecord:
    return storage.upsert_device(payload)


@app.get('/api/v1/admin/overview', response_model=AdminOverview)
def admin_overview(x_admin_token: str | None = Header(default=None)) -> AdminOverview:
    _require_admin_token(x_admin_token)
    return storage.get_admin_overview()


@app.get('/api/v1/admin/sessions', response_model=list[AdminSessionItem])
def admin_sessions(x_admin_token: str | None = Header(default=None)) -> list[AdminSessionItem]:
    _require_admin_token(x_admin_token)
    return storage.list_admin_sessions(limit=100)


@app.get('/api/v1/admin/sessions/{session_id}', response_model=SessionDetail)
def admin_session_detail(session_id: str, x_admin_token: str | None = Header(default=None)) -> SessionDetail:
    _require_admin_token(x_admin_token)
    try:
        return storage.get_session_detail(session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail='Session not found') from exc


@app.get('/api/v1/admin/devices', response_model=list[DeviceRecord])
def admin_devices(x_admin_token: str | None = Header(default=None)) -> list[DeviceRecord]:
    _require_admin_token(x_admin_token)
    return storage.list_devices()


@app.get('/api/v1/admin/alerts', response_model=list[AlertRecord])
def admin_alerts(x_admin_token: str | None = Header(default=None)) -> list[AlertRecord]:
    _require_admin_token(x_admin_token)
    return storage.list_alerts(limit=100)


def _require_admin_token(token: str | None) -> None:
    if settings.admin_token and token != settings.admin_token:
        raise HTTPException(status_code=401, detail='Invalid admin token')
