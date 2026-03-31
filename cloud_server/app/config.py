from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class Settings:
    app_env: str = os.getenv('CARDIO_APP_ENV', 'development')
    analysis_execution_mode: str = os.getenv('CARDIO_ANALYSIS_EXECUTION_MODE', 'inline')
    analysis_provider_route: str = os.getenv('CARDIO_ANALYSIS_PROVIDER', 'closed_source')
    llm_api_base_url: str = os.getenv('CARDIO_LLM_API_BASE_URL', '').strip()
    llm_api_key: str = os.getenv('CARDIO_LLM_API_KEY', '').strip()
    llm_model: str = os.getenv('CARDIO_LLM_MODEL', '').strip()
    llm_prompt_version: str = os.getenv('CARDIO_LLM_PROMPT_VERSION', 'v1')
    local_llm_base_url: str = os.getenv('CARDIO_LOCAL_LLM_BASE_URL', '').strip()
    local_llm_model: str = os.getenv('CARDIO_LOCAL_LLM_MODEL', '').strip()
    mqtt_broker_host: str = os.getenv('CARDIO_MQTT_HOST', '127.0.0.1').strip()
    mqtt_broker_port: int = int(os.getenv('CARDIO_MQTT_PORT', '1883'))
    mqtt_username: str = os.getenv('CARDIO_MQTT_USERNAME', '').strip()
    mqtt_password: str = os.getenv('CARDIO_MQTT_PASSWORD', '').strip()
    mqtt_topic_prefix: str = os.getenv('CARDIO_MQTT_TOPIC_PREFIX', 'cardio').strip()
    admin_token: str = os.getenv('CARDIO_ADMIN_TOKEN', 'change-me').strip()


settings = Settings()
