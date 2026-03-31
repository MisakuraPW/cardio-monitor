from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, Field


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def make_id(prefix: str) -> str:
    return f"{prefix}-{uuid4().hex[:12]}"


class SessionCreate(BaseModel):
    deviceId: str
    sourceMode: str
    channelKeys: list[str] = Field(default_factory=list)
    startedAt: str = Field(default_factory=utcnow_iso)


class SessionRecord(SessionCreate):
    id: str
    updatedAt: str


class UploadCreate(BaseModel):
    summary: dict[str, Any] = Field(default_factory=dict)
    excerpts: dict[str, Any] = Field(default_factory=dict)


class UploadRecord(BaseModel):
    id: str
    sessionId: str
    status: str
    createdAt: str
    lastMessage: str = ''


class AnalysisJobCreate(BaseModel):
    sessionId: str


class AnalysisJobRecord(BaseModel):
    id: str
    sessionId: str
    status: str
    createdAt: str
    completedAt: str | None = None
    summary: str = ''


class ReportFinding(BaseModel):
    title: str
    severity: str
    detail: str


class ModelTrace(BaseModel):
    provider: str
    route: str
    status: str
    model: str | None = None
    promptVersion: str | None = None
    note: str = ''


class MedicalReport(BaseModel):
    sessionId: str
    generatedAt: str
    summary: str
    recommendations: list[str] = Field(default_factory=list)
    findings: list[ReportFinding] = Field(default_factory=list)
    confidence: float | None = None
    modelTrace: ModelTrace | None = None


class ChannelDescriptorPayload(BaseModel):
    key: str
    label: str
    unit: str
    sampleRate: float
    colorHex: str = '#247BA0'
    enabled: bool = True


class ChannelCatalogCreate(BaseModel):
    sessionId: str
    deviceId: str
    sourceMode: str = 'wifi_mqtt'
    channels: list[ChannelDescriptorPayload] = Field(default_factory=list)


class ChannelCatalogRecord(ChannelCatalogCreate):
    id: str
    createdAt: str


class DeviceUpsert(BaseModel):
    deviceId: str
    sourceMode: str
    lastStatus: str = 'online'
    metadata: dict[str, Any] = Field(default_factory=dict)


class DeviceRecord(BaseModel):
    deviceId: str
    sourceMode: str
    lastSeenAt: str
    lastStatus: str
    metadata: dict[str, Any] = Field(default_factory=dict)


class IngestSessionOpen(BaseModel):
    deviceId: str
    sourceMode: str = 'wifi_mqtt'
    channelKeys: list[str] = Field(default_factory=list)
    startedAt: str = Field(default_factory=utcnow_iso)
    metadata: dict[str, Any] = Field(default_factory=dict)


class FrameBatchIngest(BaseModel):
    sessionId: str
    deviceId: str
    channelKey: str
    sampleRate: float
    unit: str = 'a.u.'
    quality: float = 1.0
    startTimestampMs: int
    endTimestampMs: int | None = None
    samples: list[float] = Field(default_factory=list)
    transport: str = 'mqtt'
    metadata: dict[str, Any] = Field(default_factory=dict)


class RawChunkRecord(BaseModel):
    id: str
    sessionId: str
    channelKey: str
    sourceType: str
    objectKey: str
    createdAt: str
    startTimestampMs: int
    endTimestampMs: int
    sampleCount: int
    metadata: dict[str, Any] = Field(default_factory=dict)


class AlertCreate(BaseModel):
    sessionId: str
    deviceId: str
    severity: str
    message: str
    payload: dict[str, Any] = Field(default_factory=dict)


class AlertRecord(AlertCreate):
    id: str
    createdAt: str


class AdminOverview(BaseModel):
    deviceCount: int
    sessionCount: int
    uploadCount: int
    analysisJobCount: int
    reportCount: int
    rawChunkCount: int
    alertCount: int
    latestSessions: list[SessionRecord] = Field(default_factory=list)


class AdminSessionItem(BaseModel):
    session: SessionRecord
    latestUpload: UploadRecord | None = None
    latestJob: AnalysisJobRecord | None = None
    hasReport: bool = False
    rawChunkCount: int = 0


class SessionDetail(BaseModel):
    session: SessionRecord
    uploads: list[UploadRecord] = Field(default_factory=list)
    jobs: list[AnalysisJobRecord] = Field(default_factory=list)
    report: MedicalReport | None = None
    catalogs: list[ChannelCatalogRecord] = Field(default_factory=list)
    rawChunks: list[RawChunkRecord] = Field(default_factory=list)
    alerts: list[AlertRecord] = Field(default_factory=list)
