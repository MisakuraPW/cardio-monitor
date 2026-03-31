from __future__ import annotations

from typing import Any

from .models import MedicalReport, ModelTrace, ReportFinding, utcnow_iso


def build_rule_report(
    *,
    session_id: str,
    summary: dict[str, Any],
    excerpts: dict[str, Any] | None = None,
) -> MedicalReport:
    excerpts = excerpts or {}
    channels = summary.get('channels', {}) or {}
    duration = float(summary.get('durationSeconds', 0) or 0)
    quality = float(summary.get('qualityScore', 0) or 0)

    findings: list[ReportFinding] = []
    recommendations: list[str] = []

    if not channels:
        findings.append(
            ReportFinding(
                title='未收到有效监测数据',
                severity='high',
                detail='当前会话未上传可用于分析的通道摘要，建议先完成采集或检查导入格式。',
            )
        )
        recommendations.append('确认设备或文件输入是否正常，再重新发起一次采集。')
    else:
        findings.append(
            ReportFinding(
                title='多源通道接入情况',
                severity='info',
                detail=f'本次会话共检测到 {len(channels)} 个通道，满足后续多通道联调与报告回传流程。',
            )
        )

    if duration < 10:
        findings.append(
            ReportFinding(
                title='监测时长偏短',
                severity='medium',
                detail=f'当前有效监测时长约 {duration:.1f} 秒，首版规则分析更适合至少 10 秒以上的数据窗口。',
            )
        )
        recommendations.append('适当延长采集时长，以便后续特征提取和模型分析更稳定。')
    else:
        findings.append(
            ReportFinding(
                title='监测时长达标',
                severity='info',
                detail=f'当前有效监测时长约 {duration:.1f} 秒，满足首版演示级分析流程。',
            )
        )

    if quality < 0.75:
        findings.append(
            ReportFinding(
                title='整体信号质量偏低',
                severity='medium',
                detail=f'当前整体质量评分约为 {quality:.2f}，可能存在传感器接触不稳、噪声较大或数据缺失。',
            )
        )
        recommendations.append('检查电极、探头、麦克风与传感器贴合情况，降低运动干扰后再次采集。')
    else:
        findings.append(
            ReportFinding(
                title='整体信号质量可用',
                severity='info',
                detail=f'当前整体质量评分约为 {quality:.2f}，适合继续进行上传、分析和报告闭环验证。',
            )
        )

    poor_channels: list[str] = []
    flat_channels: list[str] = []
    for channel_key, channel_summary in channels.items():
        mean_quality = float(channel_summary.get('meanQuality', 1) or 0)
        value_range = float(channel_summary.get('max', 0) or 0) - float(channel_summary.get('min', 0) or 0)
        if mean_quality < 0.7:
            poor_channels.append(channel_key)
        if abs(value_range) < 1e-4:
            flat_channels.append(channel_key)

    if poor_channels:
        findings.append(
            ReportFinding(
                title='部分通道质量不足',
                severity='medium',
                detail=f'以下通道质量评分偏低: {", ".join(poor_channels)}。建议重点检查这些通道的采集链路。',
            )
        )
    if flat_channels:
        findings.append(
            ReportFinding(
                title='部分通道波形近乎平直',
                severity='medium',
                detail=f'以下通道振幅范围极小: {", ".join(flat_channels)}。这通常意味着传感器未接入或文件列数据异常。',
            )
        )

    if excerpts:
        findings.append(
            ReportFinding(
                title='已收到上传片段',
                severity='info',
                detail=f'云端已收到 {len(excerpts)} 个通道的最近波形片段，可作为后续模型推理或报告渲染输入。',
            )
        )

    recommendations.append('当前报告仅用于调试演示，不构成医疗诊断结论。')
    recommendations = list(dict.fromkeys(recommendations))

    summary_text = (
        f'本次会话包含 {len(channels)} 个通道，监测时长约 {duration:.1f} 秒，'
        f'整体质量评分 {quality:.2f}。首版云端已完成上传、规则分析与报告回传闭环。'
    )

    return MedicalReport(
        sessionId=session_id,
        generatedAt=utcnow_iso(),
        summary=summary_text,
        recommendations=recommendations,
        findings=findings,
        confidence=0.62 if channels else 0.35,
        modelTrace=ModelTrace(
            provider='rules_v1',
            route='builtin',
            status='completed',
            model='rules_v1',
            promptVersion='rules_v1',
            note='规则分析已完成，可作为闭源或开源模型的兜底结果。',
        ),
    )


def build_report(
    *,
    session_id: str,
    summary: dict[str, Any],
    excerpts: dict[str, Any] | None = None,
) -> MedicalReport:
    return build_rule_report(session_id=session_id, summary=summary, excerpts=excerpts)
