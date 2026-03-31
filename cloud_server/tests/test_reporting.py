import unittest

from app.reporting import build_report


class ReportingTests(unittest.TestCase):
    def test_build_report_contains_quality_finding(self) -> None:
        report = build_report(
            session_id='session-test',
            summary={
                'durationSeconds': 6.0,
                'qualityScore': 0.52,
                'channels': {
                    'ecg': {
                        'samples': 128,
                        'min': -0.2,
                        'max': 1.1,
                        'mean': 0.05,
                        'durationSeconds': 6.0,
                        'meanQuality': 0.5,
                    }
                },
            },
            excerpts={'ecg': [0.01, 0.02, 0.5]},
        )
        self.assertEqual(report.sessionId, 'session-test')
        self.assertTrue(any(item.title == '整体信号质量偏低' for item in report.findings))
        self.assertTrue(report.recommendations)
        self.assertIsNotNone(report.modelTrace)
        self.assertGreater(report.confidence or 0, 0)


if __name__ == '__main__':
    unittest.main()
