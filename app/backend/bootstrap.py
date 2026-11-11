from pathlib import Path

from api import connect

with connect() as db:
    db.execute("SELECT pg_advisory_xact_lock(421907)")
    db.execute(Path(__file__).with_name("schema.sql").read_text(encoding="utf-8"))
