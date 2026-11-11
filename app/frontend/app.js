"use strict";

const byId = (id) => document.getElementById(id);

async function api(path, options) {
  const response = await fetch(path, { ...options, signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error(String(response.status));
  if (response.status !== 204) return response.json();
}

async function refreshStatus() {
  const readiness = byId("readiness");
  try {
    const health = await api("/health/ready");
    if (health.status !== "ready") throw new Error("Unexpected readiness response");
    readiness.textContent = "Ready";
    readiness.dataset.state = "ready";
  } catch {
    readiness.textContent = "Unavailable";
    readiness.dataset.state = "error";
  }
  try {
    const version = await api("/api/version");
    byId("release").textContent = version.release;
    byId("environment").textContent = version.environment;
  } catch {
    byId("release").textContent = "Unavailable";
    byId("environment").textContent = "Unavailable";
  }
}

async function refreshNotes() {
  const list = byId("notes");
  const state = byId("note-state");
  try {
    const notes = await api("/api/notes");
    list.replaceChildren(...notes.map((note) => {
      const item = document.createElement("li");
      const time = document.createElement("time");
      time.dateTime = new Date(note.created_at).toISOString();
      time.textContent = new Date(note.created_at).toLocaleString();
      const text = document.createElement("p");
      text.textContent = note.text;
      item.append(time, text);
      return item;
    }));
    state.textContent = notes.length ? "" : "No notes yet.";
  } catch {
    list.replaceChildren();
    state.textContent = "Could not load notes. Refresh to try again.";
  }
}

byId("note-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = byId("note-text");
  const button = event.currentTarget.querySelector("button");
  const feedback = byId("feedback");
  if (!input.value.trim()) {
    feedback.textContent = "Enter a note.";
    input.focus();
    return;
  }
  button.disabled = true;
  feedback.textContent = "Saving…";
  try {
    await api("/api/notes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: input.value }),
    });
    input.value = "";
    feedback.textContent = "Note saved.";
    await refreshNotes();
  } catch {
    feedback.textContent = "Could not confirm the save. Refresh to check your notes.";
  } finally {
    button.disabled = false;
    input.focus();
  }
});

void refreshStatus();
void refreshNotes();
setInterval(refreshStatus, 30000);
