from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Protocol
from urllib import error, request

from .config import Settings
from .models import ModelTrace, ReportFinding, SessionRecord


@dataclass
class ProviderOutput:
    summaryAppendix: str = ''
    findings: list[ReportFinding] | None = None
    recommendations: list[str] | None = None
    confidence: float | None = None
    modelTrace: ModelTrace | None = None


class AnalysisProvider(Protocol):
    def analyze(
        self,
        *,
        session: SessionRecord,
        features: dict[str, Any],
        excerpts: dict[str, Any],
        context: dict[str, Any],
    ) -> ProviderOutput:
        ...


class ClosedSourceProvider:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def analyze(
        self,
        *,
        session: SessionRecord,
        features: dict[str, Any],
        excerpts: dict[str, Any],
        context: dict[str, Any],
    ) -> ProviderOutput:
        if not (self.settings.llm_api_base_url and self.settings.llm_api_key and self.settings.llm_model):
            return ProviderOutput(
                summaryAppendix='闭源模型接口尚未配置，当前返回规则分析结果作为默认报告。',
                recommendations=['如需接入闭源模型，请配置 API Base URL、API Key 和模型名。'],
                modelTrace=ModelTrace(
                    provider='closed_source',
                    route='closed_source',
                    status='not_configured',
                    model=self.settings.llm_model or None,
                    promptVersion=self.settings.llm_prompt_version,
                    note='未检测到闭源模型配置，自动跳过外部推理。',
                ),
            )

        body = {
            'model': self.settings.llm_model,
            'messages': [
                {
                    'role': 'system',
                    'content': (
                        '你是医学监测报告助手。请根据输入的监测摘要与规则分析结果，'
                        '返回 JSON，字段必须包含 summaryAppendix, findings, recommendations, confidence。'
                    ),
                },
                {
                    'role': 'user',
                    'content': json.dumps(
                        {
                            'session': session.model_dump(),
                            'features': features,
                            'excerpts': excerpts,
                            'context': context,
                        },
                        ensure_ascii=False,
                    ),
                },
            ],
            'temperature': 0.2,
        }
        endpoint = self.settings.llm_api_base_url.rstrip('/') + '/chat/completions'
        req = request.Request(
            endpoint,
            data=json.dumps(body).encode('utf-8'),
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {self.settings.llm_api_key}',
            },
            method='POST',
        )
        try:
            with request.urlopen(req, timeout=25) as response:
                payload = json.loads(response.read().decode('utf-8'))
        except error.URLError as exc:
            return ProviderOutput(
                summaryAppendix='闭源模型调用失败，已回退到规则分析结果。',
                recommendations=['检查云端模型 API 地址、密钥和网络连通性后再次尝试。'],
                modelTrace=ModelTrace(
                    provider='closed_source',
                    route='closed_source',
                    status='error',
                    model=self.settings.llm_model,
                    promptVersion=self.settings.llm_prompt_version,
                    note=str(exc),
                ),
            )

        return _parse_openai_compatible_response(
            payload=payload,
            provider='closed_source',
            route='closed_source',
            model=self.settings.llm_model,
            prompt_version=self.settings.llm_prompt_version,
        )


class OpenSourceProvider:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def analyze(
        self,
        *,
        session: SessionRecord,
        features: dict[str, Any],
        excerpts: dict[str, Any],
        context: dict[str, Any],
    ) -> ProviderOutput:
        if not (self.settings.local_llm_base_url and self.settings.local_llm_model):
            return ProviderOutput(
                summaryAppendix='开源自部署模型接口已预留，但当前未配置。',
                recommendations=['后续接入本地模型服务时，只需补充本地模型地址与模型名。'],
                modelTrace=ModelTrace(
                    provider='open_source',
                    route='open_source',
                    status='not_configured',
                    model=self.settings.local_llm_model or None,
                    promptVersion='v1',
                    note='保留接口，暂不执行本地模型推理。',
                ),
            )

        body = {
            'model': self.settings.local_llm_model,
            'messages': [
                {
                    'role': 'system',
                    'content': '请用 JSON 返回心肺监测分析补充结果。',
                },
                {
                    'role': 'user',
                    'content': json.dumps(
                        {
                            'session': session.model_dump(),
                            'features': features,
                            'excerpts': excerpts,
                            'context': context,
                        },
                        ensure_ascii=False,
                    ),
                },
            ],
            'temperature': 0.2,
        }
        endpoint = self.settings.local_llm_base_url.rstrip('/') + '/chat/completions'
        req = request.Request(
            endpoint,
            data=json.dumps(body).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST',
        )
        try:
            with request.urlopen(req, timeout=45) as response:
                payload = json.loads(response.read().decode('utf-8'))
        except error.URLError as exc:
            return ProviderOutput(
                summaryAppendix='开源模型调用失败，已保留规则分析结果。',
                recommendations=['检查本地推理服务是否启动，并确认服务器算力与模型镜像可用。'],
                modelTrace=ModelTrace(
                    provider='open_source',
                    route='open_source',
                    status='error',
                    model=self.settings.local_llm_model,
                    promptVersion='v1',
                    note=str(exc),
                ),
            )

        return _parse_openai_compatible_response(
            payload=payload,
            provider='open_source',
            route='open_source',
            model=self.settings.local_llm_model,
            prompt_version='v1',
        )


def build_analysis_provider(settings: Settings) -> AnalysisProvider:
    if settings.analysis_provider_route == 'open_source':
        return OpenSourceProvider(settings)
    return ClosedSourceProvider(settings)


def _parse_openai_compatible_response(
    *,
    payload: dict[str, Any],
    provider: str,
    route: str,
    model: str,
    prompt_version: str,
) -> ProviderOutput:
    message = ''
    choices = payload.get('choices') or []
    if choices:
        message = choices[0].get('message', {}).get('content', '') or ''

    parsed: dict[str, Any]
    try:
        parsed = json.loads(message) if message else {}
    except json.JSONDecodeError:
        parsed = {'summaryAppendix': message}

    findings = []
    for item in parsed.get('findings', []) or []:
        try:
            findings.append(ReportFinding(**item))
        except TypeError:
            continue

    return ProviderOutput(
        summaryAppendix=str(parsed.get('summaryAppendix', '') or ''),
        findings=findings,
        recommendations=[str(item) for item in (parsed.get('recommendations') or [])],
        confidence=float(parsed.get('confidence')) if parsed.get('confidence') is not None else None,
        modelTrace=ModelTrace(
            provider=provider,
            route=route,
            status='completed',
            model=model,
            promptVersion=prompt_version,
            note='模型推理完成。',
        ),
    )
