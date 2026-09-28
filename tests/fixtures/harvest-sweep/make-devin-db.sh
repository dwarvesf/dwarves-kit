#!/bin/bash
# make-devin-db.sh <path> [--rename-column]
# Builds a fixture devin sessions.db. The schema is the real one (read with
# `sqlite3 -readonly <db> .schema` on the Mini), trimmed to the columns the adapter uses
# plus a few it ignores. The chat_message JSON shape is spec-derived, not observed.
# --rename-column renames sessions.last_activity_at, the drifted schema for AC14.
set -e
DB="$1"
[ -n "$DB" ] || { echo "usage: $0 <path> [--rename-column]" >&2; exit 2; }
[ -e "$DB" ] && mv -f "$DB" "$DB.old"

sqlite3 "$DB" <<'SQL'
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  working_directory TEXT NOT NULL,
  backend_type TEXT NOT NULL,
  model TEXT NOT NULL,
  agent_mode TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_activity_at INTEGER NOT NULL, title TEXT, main_chain_id INTEGER, hidden INTEGER NOT NULL DEFAULT 0);
CREATE TABLE message_nodes (
  row_id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  node_id INTEGER NOT NULL,
  parent_node_id INTEGER,
  chat_message TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE(session_id, node_id)
);
INSERT INTO sessions (id, working_directory, backend_type, model, agent_mode, created_at, last_activity_at, main_chain_id, hidden) VALUES
  ('s-main',   '/work/app',    'x', 'm', 'a', 1000, 1900, 7,    0),
  ('s-null',   '/work/other',  'x', 'm', 'a', 2000, 2900, NULL, 0),
  ('s-hidden', '/work/hidden', 'x', 'm', 'a', 3000, 3900, 2,    1);

-- s-main: chain 1 -> 2 -> 3 -> 6 -> 7; nodes 4 and 5 are an abandoned branch off node 2.
INSERT INTO message_nodes (session_id, node_id, parent_node_id, chat_message, created_at) VALUES
  ('s-main', 1, NULL, '{"role":"system","content":"INJECTED RULES"}', 1001),
  ('s-main', 2, 1,    '{"role":"user","content":"Fix the flaky login test"}', 1002),
  ('s-main', 3, 2,    '{"role":"assistant","content":"Reading the test.","tool_calls":[{"id":"c1","type":"function","function":{"name":"read_file","arguments":"{}"}}]}', 1003),
  ('s-main', 4, 2,    '{"role":"assistant","content":"ABANDONED BRANCH reply"}', 1004),
  ('s-main', 5, 4,    '{"role":"user","content":"ABANDONED BRANCH follow-up"}', 1005),
  ('s-main', 6, 3,    '{"role":"tool","tool_call_id":"c1","content":"def test_login(): pass"}', 1006),
  ('s-main', 7, 6,    '{"role":"assistant","content":"Fixed with a retry."}', 1007);

-- s-null: no main chain, so every node by node_id; content as a block list on node 3.
INSERT INTO message_nodes (session_id, node_id, parent_node_id, chat_message, created_at) VALUES
  ('s-null', 1, NULL, '{"role":"system","content":"INJECTED RULES"}', 2001),
  ('s-null', 2, 1,    '{"role":"user","content":"Summarize the repo"}', 2002),
  ('s-null', 3, 2,    '{"role":"assistant","content":[{"type":"text","text":"It is a CLI."}]}', 2003),
  ('s-null', 4, 3,    '{"role":"user","content":"Thanks"}', 2004),
  ('s-null', 5, 4,    '{"role":"assistant","content":"Done."}', 2005);

INSERT INTO message_nodes (session_id, node_id, parent_node_id, chat_message, created_at) VALUES
  ('s-hidden', 1, NULL, '{"role":"user","content":"hidden session"}', 3001),
  ('s-hidden', 2, 1,    '{"role":"assistant","content":"hidden reply"}', 3002);
SQL

if [ "$2" = "--rename-column" ]; then
  sqlite3 "$DB" "ALTER TABLE sessions RENAME COLUMN last_activity_at TO last_active_at;"
fi
