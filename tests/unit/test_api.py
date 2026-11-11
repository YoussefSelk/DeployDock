import unittest
from unittest.mock import patch

from api import app


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_liveness_and_version_are_independent_of_database(self):
        with patch("api.connect", side_effect=AssertionError("database accessed")):
            self.assertEqual(self.client.get("/health/live").json, {"status": "live"})
            self.assertIn("release", self.client.get("/api/version").json)

    def test_readiness_fails_closed_without_database(self):
        import psycopg

        with patch("api.connect", side_effect=psycopg.OperationalError("private details")):
            response = self.client.get("/health/ready")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json, {"status": "unavailable"})

    def test_validation_rejects_malformed_or_invalid_writes(self):
        with patch("api.connect", side_effect=AssertionError("database accessed")):
            for data in ({}, {"text": 3}, {"text": " "}, {"text": "x" * 241}, {"text": "\x00"}, []):
                with self.subTest(data=data):
                    self.assertEqual(self.client.post("/api/notes", json=data).status_code, 400)
            self.assertEqual(self.client.post("/api/notes", data="{", content_type="application/json").status_code, 400)
            self.assertEqual(self.client.post("/api/notes", json={"text": "x" * 9000}).status_code, 413)

    def test_unknown_id_has_json_404(self):
        self.assertEqual(self.client.get("/api/notes/not-a-uuid").status_code, 404)
