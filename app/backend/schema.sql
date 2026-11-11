CREATE TABLE IF NOT EXISTS notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    text text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 240),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notes_created_at_idx ON notes (created_at DESC, id DESC);
