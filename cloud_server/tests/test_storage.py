import tempfile
import unittest
from pathlib import Path

from app.blob_store import LocalBlobStore
from app.models import AnalysisJobCreate, FrameBatchIngest, SessionCreate, UploadCreate
from app.storage import SQLiteStorage


class StorageTests(unittest.TestCase):
    def test_storage_supports_admin_overview_and_raw_chunks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = Path(temp_dir) / 'test.db'
            blob_root = Path(temp_dir) / 'blob'
            storage = SQLiteStorage(db_path=str(db_path), blob_store=LocalBlobStore(str(blob_root)))

            session = storage.create_session(
                SessionCreate(deviceId='esp32-01', sourceMode='wifi_mqtt', channelKeys=['ecg'])
            )
            storage.create_upload(
                session.id,
                UploadCreate(summary={'durationSeconds': 12, 'qualityScore': 0.9, 'channels': {'ecg': {'meanQuality': 0.9, 'min': 0, 'max': 1}}}, excerpts={'ecg': [0.1, 0.2]}),
            )
            chunk = storage.ingest_frame_batch(
                FrameBatchIngest(
                    sessionId=session.id,
                    deviceId='esp32-01',
                    channelKey='ecg',
                    sampleRate=250,
                    startTimestampMs=1000,
                    endTimestampMs=1036,
                    samples=[0.1, 0.2, 0.3],
                )
            )
            job = storage.create_analysis_job(AnalysisJobCreate(sessionId=session.id))

            overview = storage.get_admin_overview()
            detail = storage.get_session_detail(session.id)

            self.assertEqual(overview.sessionCount, 1)
            self.assertEqual(overview.rawChunkCount, 1)
            self.assertEqual(chunk.sampleCount, 3)
            self.assertEqual(job.status, 'queued')
            self.assertEqual(detail.session.id, session.id)
            self.assertEqual(len(detail.rawChunks), 1)
            self.assertTrue((blob_root / chunk.objectKey).exists())
            storage.close()


if __name__ == '__main__':
    unittest.main()

