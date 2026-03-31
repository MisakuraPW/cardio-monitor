from __future__ import annotations

from typing import Any

from .analysis_provider import build_analysis_provider
from .config import Settings
from .models import MedicalReport, ReportFinding
from .reporting import build_rule_report
from .storage import SQLiteStorage


def process_analysis_job(
    storage: SQLiteStorage,
    settings: Settings,
    job_id: str,
) -> MedicalReport:
    job = storage.start_analysis_job(job_id)
    session = storage.get_session(job.sessionId)
    if session is None:
        storage.fail_analysis_job(job_id, 'session_not_found')
        raise KeyError(job.sessionId)

    upload_payload = storage.get_latest_upload_payload(job.sessionId)
    if upload_payload is None:
        storage.fail_analysis_job(job_id, 'upload_payload_not_found')
        raise KeyError(job.sessionId)

    summary, excerpts = upload_payload
    try:
        rule_report = build_rule_report(session_id=session.id, summary=summary, excerpts=excerpts)
        provider = build_analysis_provider(settings)
        provider_output = provider.analyze(
            session=session,
            features=summary,
            excerpts=excerpts,
            context={'ruleReport': rule_report.model_dump()},
        )

        report = _merge_reports(
            rule_report,
            provider_output.summaryAppendix,
            provider_output.findings or [],
            provider_output.recommendations or [],
            provider_output.confidence,
            provider_output.modelTrace,
        )
        storage.save_report(report)
        storage.complete_analysis_job(
            job_id,
            summary=f"{report.modelTrace.provider if report.modelTrace else 'rules_v1'} finished and report persisted",
        )
        return report
    except Exception as exc:
        storage.fail_analysis_job(job_id, f'analysis_failed: {exc}')
        raise


def process_pending_jobs(storage: SQLiteStorage, settings: Settings, limit: int = 5) -> int:
    processed = 0
    for job in storage.list_analysis_jobs(status='queued', limit=limit):
        process_analysis_job(storage, settings, job.id)
        processed += 1
    return processed


def build_feature_snapshot(summary: dict[str, Any], excerpts: dict[str, Any]) -> dict[str, Any]:
    channels = summary.get('channels', {}) or {}
    local_analysis = summary.get('localAnalysis', {}) or {}
    return {
        'durationSeconds': summary.get('durationSeconds', 0),
        'qualityScore': summary.get('qualityScore', 0),
        'channelCount': len(channels),
        'excerptChannelCount': len(excerpts),
        'localAnalysis': local_analysis,
    }


def _merge_reports(
    rule_report: MedicalReport,
    summary_appendix: str,
    provider_findings: list[ReportFinding],
    provider_recommendations: list[str],
    confidence: float | None,
    model_trace,
) -> MedicalReport:
    findings = [*rule_report.findings, *provider_findings]

    dedup_findings: list[ReportFinding] = []
    seen = set()
    for item in findings:
        signature = (item.title, item.severity, item.detail)
        if signature in seen:
            continue
        seen.add(signature)
        dedup_findings.append(item)

    recommendations = list(dict.fromkeys([*rule_report.recommendations, *provider_recommendations]))
    summary = rule_report.summary
    if summary_appendix:
        summary = f'{summary} {summary_appendix}'.strip()

    return MedicalReport(
        sessionId=rule_report.sessionId,
        generatedAt=rule_report.generatedAt,
        summary=summary,
        recommendations=recommendations,
        findings=dedup_findings,
        confidence=confidence if confidence is not None else rule_report.confidence,
        modelTrace=model_trace or rule_report.modelTrace,
    )
