import os

import psycopg
from flask import Flask, jsonify, request
from psycopg.rows import dict_row
from werkzeug.exceptions import HTTPException

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8192


def connect():
    with open(os.environ["DB_PASSWORD_FILE"], encoding="utf-8") as secret:
        password = secret.read().strip()
    return psycopg.connect(
        host=os.getenv("DB_HOST", "db"),
        dbname="deploydock",
        user="deploydock",
        password=password,
        connect_timeout=3,
        options="-c statement_timeout=3000",
        row_factory=dict_row,
    )


@app.errorhandler(HTTPException)
def http_error(error):
    return {"error": error.name}, error.code


@app.errorhandler(psycopg.Error)
@app.errorhandler(OSError)
def database_error(error):
    app.logger.warning("Database operation failed (%s)", type(error).__name__)
    return {"status": "unavailable"}, 503


@app.get("/health/live")
def live():
    return {"status": "live"}


@app.get("/health/ready")
def ready():
    with connect() as db:
        db.execute("SELECT id, text, created_at FROM notes LIMIT 1").fetchone()
    return {"status": "ready"}


@app.get("/api/version")
def version():
    return {"release": os.getenv("RELEASE_ID", "dev"), "environment": os.getenv("APP_ENV", "local")}


@app.get("/api/notes")
def notes():
    with connect() as db:
        rows = db.execute(
            "SELECT id, text, created_at FROM notes ORDER BY created_at DESC, id DESC LIMIT 50"
        ).fetchall()
    return jsonify(rows)


@app.post("/api/notes")
def create_note():
    data = request.get_json(silent=True)
    text = data.get("text") if isinstance(data, dict) else None
    if not isinstance(text, str) or not 1 <= len(text.strip()) <= 240 or "\x00" in text:
        return {"error": "Enter a note between 1 and 240 characters."}, 400
    if any(0xD800 <= ord(character) <= 0xDFFF for character in text):
        return {"error": "Enter valid Unicode text."}, 400
    with connect() as db:
        note = db.execute(
            "INSERT INTO notes (text) VALUES (%s) RETURNING id, text, created_at", (text.strip(),)
        ).fetchone()
    return note, 201


@app.get("/api/notes/<uuid:note_id>")
def get_note(note_id):
    with connect() as db:
        note = db.execute("SELECT id, text, created_at FROM notes WHERE id = %s", (note_id,)).fetchone()
    return note if note else ({"error": "Note not found."}, 404)


@app.delete("/api/notes/<uuid:note_id>")
def delete_note(note_id):
    with connect() as db:
        deleted = db.execute("DELETE FROM notes WHERE id = %s RETURNING id", (note_id,)).fetchone()
    return ("", 204) if deleted else ({"error": "Note not found."}, 404)
