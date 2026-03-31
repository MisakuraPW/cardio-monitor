from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from .blob_store import LocalBlobStore
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
    MedicalReport,
    RawChunkRecord,
    SessionCreate,
    SessionDetail,
    SessionRecord,
    UploadCreate,
    UploadRecord,
    make_id,
    utcnow_iso,
)


class SQLiteStorage:
    def __init__(self, db_path: str | None = None, blob_store: LocalBlobStore | None = None) -> None:
        base_dir = Path(__file__).resolve().parent.parent / 'data'
        base_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = Path(db_path) if db_path else base_dir / 'cardio_cloud.db'
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.blob_store = blob_store or LocalBlobStore()
        self._init_schema()

    def _init_schema(self) -> None:
        self.conn.executescript(
            '''
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                device_id TEXT NOT NULL,
                source_mode TEXT NOT NULL,
                started_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                channel_keys TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS uploads (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                last_message TEXT NOT NULL,
                summary_json TEXT NOT NULL,
                excerpts_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );

            CREATE TABLE IF NOT EXISTS analysis_jobs (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                completed_at TEXT,
                summary TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );

            CREATE TABLE IF NOT EXISTS reports (
                session_id TEXT PRIMARY KEY,
                generated_at TEXT NOT NULL,
                summary TEXT NOT NULL,
                recommendations_json TEXT NOT NULL,
                findings_json TEXT NOT NULL,
                confidence REAL,
                model_trace_json TEXT,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );

            CREATE TABLE IF NOT EXISTS devices (
                device_id TEXT PRIMARY KEY,
                source_mode TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                last_status TEXT NOT NULL,
                metadata_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS channel_catalogs (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                source_mode TEXT NOT NULL,
                created_at TEXT NOT NULL,
                channels_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );

            CREATE TABLE IF NOT EXISTS raw_chunks (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                channel_key TEXT NOT NULL,
                source_type TEXT NOT NULL,
                object_key TEXT NOT NULL,
                created_at TEXT NOT NULL,
                start_timestamp_ms INTEGER NOT NULL,
                end_timestamp_ms INTEGER NOT NULL,
                sample_count INTEGER NOT NULL,
                metadata_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );

            CREATE TABLE IF NOT EXISTS alerts (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id)
            );
            '''
        )
        self._ensure_column('reports', 'confidence', 'REAL')
        self._ensure_column('reports', 'model_trace_json', 'TEXT')
        self.conn.commit()

    def _ensure_column(self, table: str, column: str, definition: str) -> None:
        columns = {
            row['name']
            for row in self.conn.execute(f'PRAGMA table_info({table})').fetchall()
        }
        if column not in columns:
            self.conn.execute(f'ALTER TABLE {table} ADD COLUMN {column} {definition}')

    def create_session(self, payload: SessionCreate) -> SessionRecord:
        record = SessionRecord(
            id=make_id('session'),
            deviceId=payload.deviceId,
            sourceMode=payload.sourceMode,
            channelKeys=payload.channelKeys,
            startedAt=payload.startedAt,
            updatedAt=utcnow_iso(),
        )
        self.conn.execute(
            'INSERT INTO sessions (id, device_id, source_mode, started_at, updated_at, channel_keys) VALUES (?, ?, ?, ?, ?, ?)',
            (
                record.id,
                record.deviceId,
                record.sourceMode,
                record.startedAt,
                record.updatedAt,
                json.dumps(record.channelKeys, ensure_ascii=False),
            ),
        )
        self.conn.commit()
        self.upsert_device(
            DeviceUpsert(
                deviceId=record.deviceId,
                sourceMode=record.sourceMode,
                lastStatus='session_opened',
                metadata={'channelKeys': record.channelKeys},
            )
        )
        return record

    def get_session(self, session_id: str) -> SessionRecord | None:
        row = self.conn.execute('SELECT * FROM sessions WHERE id = ?', (session_id,)).fetchone()
        return self._row_to_session(row) if row else None

    def list_sessions(self, limit: int = 50) -> list[SessionRecord]:
        rows = self.conn.execute(
            'SELECT * FROM sessions ORDER BY updated_at DESC LIMIT ?',
            (limit,),
        ).fetchall()
        return [self._row_to_session(row) for row in rows]

    def create_upload(self, session_id: str, payload: UploadCreate) -> UploadRecord:
        record = UploadRecord(
            id=make_id('upload'),
            sessionId=session_id,
            status='uploaded',
            createdAt=utcnow_iso(),
            lastMessage='summary_and_excerpts_received',
        )
        self.conn.execute(
            'INSERT INTO uploads (id, session_id, status, created_at, last_message, summary_json, excerpts_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (
                record.id,
                record.sessionId,
                record.status,
                record.createdAt,
                record.lastMessage,
                json.dumps(payload.summary, ensure_ascii=False),
                json.dumps(payload.excerpts, ensure_ascii=False),
            ),
        )
        self._touch_session(session_id)
        self.conn.commit()
        return record

    def list_uploads_for_session(self, session_id: str) -> list[UploadRecord]:
        rows = self.conn.execute(
            'SELECT * FROM uploads WHERE session_id = ? ORDER BY created_at DESC',
            (session_id,),
        ).fetchall()
        return [self._row_to_upload(row) for row in rows]

    def get_latest_upload_payload(self, session_id: str) -> tuple[dict[str, Any], dict[str, Any]] | None:
        row = self.conn.execute(
            'SELECT summary_json, excerpts_json FROM uploads WHERE session_id = ? ORDER BY created_at DESC LIMIT 1',
            (session_id,),
        ).fetchone()
        if not row:
            return None
        return json.loads(row['summary_json']), json.loads(row['excerpts_json'])

    def create_analysis_job(self, payload: AnalysisJobCreate) -> AnalysisJobRecord:
        record = AnalysisJobRecord(
            id=make_id('job'),
            sessionId=payload.sessionId,
            status='queued',
            createdAt=utcnow_iso(),
            completedAt=None,
            summary='',
        )
        self.conn.execute(
            'INSERT INTO analysis_jobs (id, session_id, status, created_at, completed_at, summary) VALUES (?, ?, ?, ?, ?, ?)',
            (record.id, record.sessionId, record.status, record.createdAt, record.completedAt, record.summary),
        )
        self._touch_session(payload.sessionId)
        self.conn.commit()
        return record

    def start_analysis_job(self, job_id: str) -> AnalysisJobRecord:
        self.conn.execute(
            'UPDATE analysis_jobs SET status = ? WHERE id = ? AND status = ?',
            ('running', job_id, 'queued'),
        )
        self.conn.commit()
        return self.get_analysis_job(job_id)

    def complete_analysis_job(self, job_id: str, summary: str) -> AnalysisJobRecord:
        completed_at = utcnow_iso()
        self.conn.execute(
            'UPDATE analysis_jobs SET status = ?, completed_at = ?, summary = ? WHERE id = ?',
            ('completed', completed_at, summary, job_id),
        )
        self.conn.commit()
        return self.get_analysis_job(job_id)

    def fail_analysis_job(self, job_id: str, summary: str) -> AnalysisJobRecord:
        completed_at = utcnow_iso()
        self.conn.execute(
            'UPDATE analysis_jobs SET status = ?, completed_at = ?, summary = ? WHERE id = ?',
            ('failed', completed_at, summary, job_id),
        )
        self.conn.commit()
        return self.get_analysis_job(job_id)

    def get_analysis_job(self, job_id: str) -> AnalysisJobRecord:
        row = self.conn.execute('SELECT * FROM analysis_jobs WHERE id = ?', (job_id,)).fetchone()
        if row is None:
            raise KeyError(job_id)
        return self._row_to_job(row)

    def list_analysis_jobs(self, status: str | None = None, limit: int = 50) -> list[AnalysisJobRecord]:
        if status:
            rows = self.conn.execute(
                'SELECT * FROM analysis_jobs WHERE status = ? ORDER BY created_at DESC LIMIT ?',
                (status, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                'SELECT * FROM analysis_jobs ORDER BY created_at DESC LIMIT ?',
                (limit,),
            ).fetchall()
        return [self._row_to_job(row) for row in rows]

    def list_analysis_jobs_for_session(self, session_id: str) -> list[AnalysisJobRecord]:
        rows = self.conn.execute(
            'SELECT * FROM analysis_jobs WHERE session_id = ? ORDER BY created_at DESC',
            (session_id,),
        ).fetchall()
        return [self._row_to_job(row) for row in rows]

    def save_report(self, report: MedicalReport) -> MedicalReport:
        self.conn.execute(
            'INSERT OR REPLACE INTO reports (session_id, generated_at, summary, recommendations_json, findings_json, confidence, model_trace_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (
                report.sessionId,
                report.generatedAt,
                report.summary,
                json.dumps(report.recommendations, ensure_ascii=False),
                json.dumps([item.model_dump() for item in report.findings], ensure_ascii=False),
                report.confidence,
                json.dumps(report.modelTrace.model_dump(), ensure_ascii=False) if report.modelTrace else None,
            ),
        )
        self._touch_session(report.sessionId)
        self.conn.commit()
        return report

    def get_report(self, session_id: str) -> MedicalReport | None:
        row = self.conn.execute('SELECT * FROM reports WHERE session_id = ?', (session_id,)).fetchone()
        return self._row_to_report(row) if row else None

    def upsert_device(self, payload: DeviceUpsert) -> DeviceRecord:
        now = utcnow_iso()
        self.conn.execute(
            '''
            INSERT INTO devices (device_id, source_mode, last_seen_at, last_status, metadata_json)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(device_id) DO UPDATE SET
                source_mode=excluded.source_mode,
                last_seen_at=excluded.last_seen_at,
                last_status=excluded.last_status,
                metadata_json=excluded.metadata_json
            ''',
            (
                payload.deviceId,
                payload.sourceMode,
                now,
                payload.lastStatus,
                json.dumps(payload.metadata, ensure_ascii=False),
            ),
        )
        self.conn.commit()
        return DeviceRecord(
            deviceId=payload.deviceId,
            sourceMode=payload.sourceMode,
            lastSeenAt=now,
            lastStatus=payload.lastStatus,
            metadata=payload.metadata,
        )

    def list_devices(self) -> list[DeviceRecord]:
        rows = self.conn.execute(
            'SELECT * FROM devices ORDER BY last_seen_at DESC, device_id ASC',
        ).fetchall()
        return [self._row_to_device(row) for row in rows]

    def save_channel_catalog(self, payload: ChannelCatalogCreate) -> ChannelCatalogRecord:
        record = ChannelCatalogRecord(
            id=make_id('catalog'),
            sessionId=payload.sessionId,
            deviceId=payload.deviceId,
            sourceMode=payload.sourceMode,
            channels=payload.channels,
            createdAt=utcnow_iso(),
        )
        self.conn.execute(
            'INSERT INTO channel_catalogs (id, session_id, device_id, source_mode, created_at, channels_json) VALUES (?, ?, ?, ?, ?, ?)',
            (
                record.id,
                record.sessionId,
                record.deviceId,
                record.sourceMode,
                record.createdAt,
                json.dumps([item.model_dump() for item in record.channels], ensure_ascii=False),
            ),
        )
        self._touch_session(payload.sessionId)
        self.conn.commit()
        self.upsert_device(
            DeviceUpsert(
                deviceId=payload.deviceId,
                sourceMode=payload.sourceMode,
                lastStatus='catalog_updated',
                metadata={'channelCount': len(payload.channels)},
            )
        )
        return record

    def list_catalogs_for_session(self, session_id: str) -> list[ChannelCatalogRecord]:
        rows = self.conn.execute(
            'SELECT * FROM channel_catalogs WHERE session_id = ? ORDER BY created_at DESC',
            (session_id,),
        ).fetchall()
        return [self._row_to_catalog(row) for row in rows]

    def ingest_frame_batch(self, payload: FrameBatchIngest) -> RawChunkRecord:
        chunk_id = make_id('chunk')
        end_timestamp = payload.endTimestampMs or payload.startTimestampMs
        object_key = f'raw/{payload.sessionId}/{payload.channelKey}/{chunk_id}.json'
        self.blob_store.put_json(
            object_key,
            {
                'sessionId': payload.sessionId,
                'deviceId': payload.deviceId,
                'channelKey': payload.channelKey,
                'sampleRate': payload.sampleRate,
                'unit': payload.unit,
                'quality': payload.quality,
                'startTimestampMs': payload.startTimestampMs,
                'endTimestampMs': end_timestamp,
                'samples': payload.samples,
                'transport': payload.transport,
                'metadata': payload.metadata,
            },
        )
        record = RawChunkRecord(
            id=chunk_id,
            sessionId=payload.sessionId,
            channelKey=payload.channelKey,
            sourceType=payload.transport,
            objectKey=object_key,
            createdAt=utcnow_iso(),
            startTimestampMs=payload.startTimestampMs,
            endTimestampMs=end_timestamp,
            sampleCount=len(payload.samples),
            metadata={
                'deviceId': payload.deviceId,
                'sampleRate': payload.sampleRate,
                'unit': payload.unit,
                'quality': payload.quality,
                **payload.metadata,
            },
        )
        self.conn.execute(
            'INSERT INTO raw_chunks (id, session_id, channel_key, source_type, object_key, created_at, start_timestamp_ms, end_timestamp_ms, sample_count, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (
                record.id,
                record.sessionId,
                record.channelKey,
                record.sourceType,
                record.objectKey,
                record.createdAt,
                record.startTimestampMs,
                record.endTimestampMs,
                record.sampleCount,
                json.dumps(record.metadata, ensure_ascii=False),
            ),
        )
        self._touch_session(payload.sessionId)
        self.conn.commit()
        self.upsert_device(
            DeviceUpsert(
                deviceId=payload.deviceId,
                sourceMode=payload.transport,
                lastStatus='streaming',
                metadata={'lastChannel': payload.channelKey, 'sampleRate': payload.sampleRate},
            )
        )
        return record

    def list_raw_chunks(self, session_id: str) -> list[RawChunkRecord]:
        rows = self.conn.execute(
            'SELECT * FROM raw_chunks WHERE session_id = ? ORDER BY start_timestamp_ms DESC',
            (session_id,),
        ).fetchall()
        return [self._row_to_raw_chunk(row) for row in rows]

    def create_alert(self, payload: AlertCreate) -> AlertRecord:
        record = AlertRecord(
            id=make_id('alert'),
            sessionId=payload.sessionId,
            deviceId=payload.deviceId,
            severity=payload.severity,
            message=payload.message,
            payload=payload.payload,
            createdAt=utcnow_iso(),
        )
        self.conn.execute(
            'INSERT INTO alerts (id, session_id, device_id, severity, message, created_at, payload_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (
                record.id,
                record.sessionId,
                record.deviceId,
                record.severity,
                record.message,
                record.createdAt,
                json.dumps(record.payload, ensure_ascii=False),
            ),
        )
        self._touch_session(payload.sessionId)
        self.conn.commit()
        self.upsert_device(
            DeviceUpsert(
                deviceId=payload.deviceId,
                sourceMode='mqtt',
                lastStatus=f'alert:{payload.severity}',
                metadata={'lastAlert': payload.message},
            )
        )
        return record

    def list_alerts(self, session_id: str | None = None, limit: int = 50) -> list[AlertRecord]:
        if session_id:
            rows = self.conn.execute(
                'SELECT * FROM alerts WHERE session_id = ? ORDER BY created_at DESC LIMIT ?',
                (session_id, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                'SELECT * FROM alerts ORDER BY created_at DESC LIMIT ?',
                (limit,),
            ).fetchall()
        return [self._row_to_alert(row) for row in rows]

    def get_admin_overview(self) -> AdminOverview:
        counts = {
            'deviceCount': self._count('devices'),
            'sessionCount': self._count('sessions'),
            'uploadCount': self._count('uploads'),
            'analysisJobCount': self._count('analysis_jobs'),
            'reportCount': self._count('reports'),
            'rawChunkCount': self._count('raw_chunks'),
            'alertCount': self._count('alerts'),
        }
        return AdminOverview(
            **counts,
            latestSessions=self.list_sessions(limit=6),
        )

    def list_admin_sessions(self, limit: int = 50) -> list[AdminSessionItem]:
        items: list[AdminSessionItem] = []
        for session in self.list_sessions(limit=limit):
            latest_upload = self.list_uploads_for_session(session.id)
            latest_job = self.list_analysis_jobs_for_session(session.id)
            raw_count_row = self.conn.execute(
                'SELECT COUNT(*) AS cnt FROM raw_chunks WHERE session_id = ?',
                (session.id,),
            ).fetchone()
            items.append(
                AdminSessionItem(
                    session=session,
                    latestUpload=latest_upload[0] if latest_upload else None,
                    latestJob=latest_job[0] if latest_job else None,
                    hasReport=self.get_report(session.id) is not None,
                    rawChunkCount=int(raw_count_row['cnt']) if raw_count_row else 0,
                )
            )
        return items

    def get_session_detail(self, session_id: str) -> SessionDetail:
        session = self.get_session(session_id)
        if session is None:
            raise KeyError(session_id)
        return SessionDetail(
            session=session,
            uploads=self.list_uploads_for_session(session_id),
            jobs=self.list_analysis_jobs_for_session(session_id),
            report=self.get_report(session_id),
            catalogs=self.list_catalogs_for_session(session_id),
            rawChunks=self.list_raw_chunks(session_id),
            alerts=self.list_alerts(session_id=session_id, limit=100),
        )

    def _count(self, table: str) -> int:
        row = self.conn.execute(f'SELECT COUNT(*) AS cnt FROM {table}').fetchone()
        return int(row['cnt']) if row else 0

    def _touch_session(self, session_id: str) -> None:
        self.conn.execute('UPDATE sessions SET updated_at = ? WHERE id = ?', (utcnow_iso(), session_id))

    def _row_to_session(self, row: sqlite3.Row) -> SessionRecord:
        return SessionRecord(
            id=row['id'],
            deviceId=row['device_id'],
            sourceMode=row['source_mode'],
            channelKeys=json.loads(row['channel_keys']),
            startedAt=row['started_at'],
            updatedAt=row['updated_at'],
        )

    def _row_to_upload(self, row: sqlite3.Row) -> UploadRecord:
        return UploadRecord(
            id=row['id'],
            sessionId=row['session_id'],
            status=row['status'],
            createdAt=row['created_at'],
            lastMessage=row['last_message'],
        )

    def _row_to_job(self, row: sqlite3.Row) -> AnalysisJobRecord:
        return AnalysisJobRecord(
            id=row['id'],
            sessionId=row['session_id'],
            status=row['status'],
            createdAt=row['created_at'],
            completedAt=row['completed_at'],
            summary=row['summary'],
        )

    def _row_to_report(self, row: sqlite3.Row) -> MedicalReport:
        return MedicalReport(
            sessionId=row['session_id'],
            generatedAt=row['generated_at'],
            summary=row['summary'],
            recommendations=json.loads(row['recommendations_json']),
            findings=json.loads(row['findings_json']),
            confidence=row['confidence'],
            modelTrace=json.loads(row['model_trace_json']) if row['model_trace_json'] else None,
        )

    def _row_to_device(self, row: sqlite3.Row) -> DeviceRecord:
        return DeviceRecord(
            deviceId=row['device_id'],
            sourceMode=row['source_mode'],
            lastSeenAt=row['last_seen_at'],
            lastStatus=row['last_status'],
            metadata=json.loads(row['metadata_json']),
        )

    def _row_to_catalog(self, row: sqlite3.Row) -> ChannelCatalogRecord:
        return ChannelCatalogRecord(
            id=row['id'],
            sessionId=row['session_id'],
            deviceId=row['device_id'],
            sourceMode=row['source_mode'],
            createdAt=row['created_at'],
            channels=json.loads(row['channels_json']),
        )

    def _row_to_raw_chunk(self, row: sqlite3.Row) -> RawChunkRecord:
        return RawChunkRecord(
            id=row['id'],
            sessionId=row['session_id'],
            channelKey=row['channel_key'],
            sourceType=row['source_type'],
            objectKey=row['object_key'],
            createdAt=row['created_at'],
            startTimestampMs=row['start_timestamp_ms'],
            endTimestampMs=row['end_timestamp_ms'],
            sampleCount=row['sample_count'],
            metadata=json.loads(row['metadata_json']),
        )

    def close(self) -> None:
        self.conn.close()

    def _row_to_alert(self, row: sqlite3.Row) -> AlertRecord:
        return AlertRecord(
            id=row['id'],
            sessionId=row['session_id'],
            deviceId=row['device_id'],
            severity=row['severity'],
            message=row['message'],
            createdAt=row['created_at'],
            payload=json.loads(row['payload_json']),
        )

