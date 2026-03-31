from __future__ import annotations

import json
from typing import Any

from .models import AlertCreate, ChannelCatalogCreate, ChannelDescriptorPayload, DeviceUpsert, FrameBatchIngest, IngestSessionOpen
from .storage import SQLiteStorage

try:
    import paho.mqtt.client as mqtt
except ImportError:  # pragma: no cover
    mqtt = None


class MqttIngestService:
    def __init__(self, storage: SQLiteStorage, topic_prefix: str = 'cardio') -> None:
        self.storage = storage
        self.topic_prefix = topic_prefix.rstrip('/')

    def handle_topic_message(self, topic: str, payload: str) -> None:
        segments = topic.split('/')
        if len(segments) < 3 or segments[0] != self.topic_prefix:
            return
        device_id = segments[1]
        channel_or_topic = '/'.join(segments[2:])
        body = json.loads(payload)

        if channel_or_topic == 'status':
            self.storage.upsert_device(
                DeviceUpsert(
                    deviceId=device_id,
                    sourceMode='wifi_mqtt',
                    lastStatus=str(body.get('state', 'online')),
                    metadata=body,
                )
            )
            return

        if channel_or_topic == 'catalog':
            session_id = body.get('sessionId')
            if not session_id:
                return
            channels = [ChannelDescriptorPayload(**item) for item in body.get('channels', [])]
            self.storage.save_channel_catalog(
                ChannelCatalogCreate(
                    sessionId=session_id,
                    deviceId=device_id,
                    sourceMode='wifi_mqtt',
                    channels=channels,
                )
            )
            return

        if channel_or_topic.startswith('waveform/'):
            session_id = body.get('sessionId')
            if not session_id:
                return
            channel_key = channel_or_topic.split('/', 1)[1]
            self.storage.ingest_frame_batch(
                FrameBatchIngest(
                    sessionId=session_id,
                    deviceId=device_id,
                    channelKey=channel_key,
                    sampleRate=float(body.get('sampleRate', 0) or 0),
                    unit=str(body.get('unit', 'a.u.')),
                    quality=float(body.get('quality', 1) or 1),
                    startTimestampMs=int(body.get('timestampMs', 0) or 0),
                    endTimestampMs=int(body.get('endTimestampMs', body.get('timestampMs', 0)) or 0),
                    samples=[float(item) for item in body.get('samples', [])],
                    transport='mqtt',
                    metadata={'seq': body.get('seq')},
                )
            )
            return

        if channel_or_topic == 'alerts':
            session_id = body.get('sessionId')
            if not session_id:
                return
            self.storage.create_alert(
                AlertCreate(
                    sessionId=session_id,
                    deviceId=device_id,
                    severity=str(body.get('severity', 'info')),
                    message=str(body.get('message', 'mqtt_alert')),
                    payload=body,
                )
            )


def run_forever(storage: SQLiteStorage, host: str, port: int, topic_prefix: str, username: str = '', password: str = '') -> None:  # pragma: no cover
    if mqtt is None:
        raise RuntimeError('paho-mqtt is not installed. Please install requirements.txt first.')

    service = MqttIngestService(storage=storage, topic_prefix=topic_prefix)
    client = mqtt.Client()
    if username:
        client.username_pw_set(username=username, password=password or None)

    def on_connect(client_obj, userdata, flags, rc):
        client_obj.subscribe(f'{topic_prefix}/+/status')
        client_obj.subscribe(f'{topic_prefix}/+/catalog')
        client_obj.subscribe(f'{topic_prefix}/+/waveform/+')
        client_obj.subscribe(f'{topic_prefix}/+/alerts')

    def on_message(client_obj, userdata, msg):
        service.handle_topic_message(msg.topic, msg.payload.decode('utf-8'))

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(host, port, 60)
    client.loop_forever()
