/*
# Create Emissary Core Tables

Migrates the Emissary OSINT application's data model from SQLite to Supabase/Postgres.
This is a backend-mediated app (FastAPI handles auth via its own token system),
so Supabase Auth is NOT used. RLS is enabled with permissive policies for service access.

1. New Tables
  - `coas` - Courses of Action: planned economic warfare actions with status tracking
    - `id` (text, primary key)
    - `name` (text) - COA title
    - `description` (text) - Full description
    - `target_entities` (jsonb) - JSON array of targeted entities
    - `action_type` (text) - Type of action (sanction, export_control, etc.)
    - `status` (text) - draft/under_review/approved/executing
    - `confidence` (float) - Confidence score 0-1
    - `source_analysis_id` (text) - Link to source analysis
    - `recommendations` (jsonb) - JSON array of recommended actions
    - `friendly_fire` (jsonb) - JSON array of friendly-fire risk assessments
    - `expected_effects` (jsonb) - JSON array of expected outcomes
    - `sources` (jsonb) - JSON array of source citations
    - `rationale` (text) - Analyst rationale with citation markers
    - `created_at` (timestamptz)
    - `updated_at` (timestamptz)

  - `activity_log` - System and user activity audit trail
    - `id` (bigint, auto-increment primary key)
    - `timestamp` (timestamptz)
    - `event_type` (text) - Type of event
    - `source` (text) - Origin (system/monitor/user)
    - `message` (text) - Human-readable description
    - `severity` (text) - info/warning/error
    - `related_id` (text) - Optional link to related entity

  - `briefings` - Intelligence briefings and reports
    - `id` (text, primary key)
    - `title` (text)
    - `type` (text) - coa_brief/bda_report/situation_update
    - `status` (text) - draft/reviewing/finalized
    - `reference_id` (text) - Link to related COA or entity
    - `content_markdown` (text) - Full briefing content in markdown
    - `sources` (jsonb) - JSON array of source citations
    - `created_at` (timestamptz)
    - `updated_at` (timestamptz)

  - `exercises` - Tabletop exercises
    - `id` (text, primary key)
    - `name` (text)
    - `status` (text) - planning/active/completed
    - `assessment_summary` (text) - Post-exercise assessment
    - `overall_score` (float) - Numeric score
    - `created_at` (timestamptz)

  - `injects` - Exercise inject items
    - `id` (text, primary key)
    - `exercise_id` (text, FK to exercises)
    - `inject_type` (text)
    - `target_groups` (jsonb) - JSON array
    - `content` (text)
    - `scheduled_offset` (text) - Time offset from exercise start
    - `urgency` (text) - routine/priority/immediate
    - `status` (text) - pending/delivered/responded
    - `score` (float) - Assessment score
    - `assessment_notes` (text)
    - `created_at` (timestamptz)

  - `usage_events` - Analytics and usage tracking
    - `id` (bigint, auto-increment primary key)
    - `timestamp` (timestamptz)
    - `kind` (text) - Event category (login_attempt, api_request, etc.)
    - `username` (text)
    - `feature` (text)
    - `path` (text)
    - `method` (text)
    - `status_code` (integer)
    - `latency_ms` (integer)
    - `client_ip` (text)
    - `detail` (text)

  - `watchlist_items` - Per-user risk feed watchlists
    - `id` (text, primary key)
    - `username` (text, not null)
    - `label` (text, not null)
    - `query` (text, not null)
    - `entity_kind` (text, not null)
    - `category` (text, not null)
    - `active` (boolean, default true)
    - `created_at` (timestamptz)
    - `updated_at` (timestamptz)

  - `users` - User preferences for notifications
    - `username` (text, primary key)
    - `email` (text)
    - `phone_number` (text) - E.164 format
    - `sms_enabled` (boolean, default false)
    - `email_enabled` (boolean, default false)
    - `timezone` (text, default America/New_York)
    - `created_at` (timestamptz)
    - `unsubscribed_at` (timestamptz)

  - `notification_log` - Notification delivery audit
    - `id` (bigint, auto-increment primary key)
    - `username` (text, not null)
    - `channel` (text, not null) - sms/email
    - `card_id` (text) - Risk-feed card that triggered notification
    - `digest_week` (text) - ISO week for email digests
    - `provider_message_id` (text) - Twilio SID or SendGrid ID
    - `status` (text, not null) - sent/failed/skipped_*
    - `error_text` (text)
    - `sent_at` (timestamptz)

  - `saved_entities` - Knowledge graph persistent entities
    - `id` (text, primary key)
    - `entity_id` (text, unique, not null) - Stable node ID
    - `name` (text, not null)
    - `entity_type` (text, not null)
    - `country` (text)
    - `aliases` (jsonb, default [])
    - `identifiers` (jsonb, default {})
    - `notes` (text, default '')
    - `created_by` (text) - Username that first saved it
    - `created_at` (timestamptz)
    - `updated_at` (timestamptz)

  - `saved_edges` - Knowledge graph relationships
    - `id` (text, primary key)
    - `source_id` (text, not null)
    - `target_id` (text, not null)
    - `relationship_type` (text, not null)
    - `properties` (jsonb, default {})
    - `confidence` (text, default MEDIUM)
    - `created_by` (text)
    - `created_at` (timestamptz)
    - UNIQUE(source_id, target_id, relationship_type)

  - `priorities` - Team-wide collection priorities
    - `id` (text, primary key)
    - `level` (text, not null) - country/sector/company
    - `key` (text, not null) - e.g. CN, semiconductors, Huawei
    - `weight` (float, default 1.0)
    - `label` (text, default '')
    - `notes` (text, default '')
    - `created_by` (text)
    - `created_at` (timestamptz)
    - `updated_at` (timestamptz)
    - UNIQUE(level, key)

2. Security
  - RLS enabled on ALL tables.
  - Permissive anon+authenticated policies (backend mediates auth via service role key).

3. Important Notes
  - This app uses a custom auth system (FastAPI bearer tokens), NOT Supabase Auth.
  - The backend connects with the service role key which bypasses RLS.
  - RLS policies are permissive as a safety net for any direct access patterns.
*/

-- ============================================================
-- coas
-- ============================================================
CREATE TABLE IF NOT EXISTS coas (
  id text PRIMARY KEY,
  name text,
  description text,
  target_entities jsonb DEFAULT '[]'::jsonb,
  action_type text,
  status text DEFAULT 'draft',
  confidence double precision,
  source_analysis_id text,
  recommendations jsonb DEFAULT '[]'::jsonb,
  friendly_fire jsonb DEFAULT '[]'::jsonb,
  expected_effects jsonb DEFAULT '[]'::jsonb,
  sources jsonb DEFAULT '[]'::jsonb,
  rationale text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE coas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_coas" ON coas;
CREATE POLICY "anon_select_coas" ON coas FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_coas" ON coas;
CREATE POLICY "anon_insert_coas" ON coas FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_coas" ON coas;
CREATE POLICY "anon_update_coas" ON coas FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_coas" ON coas;
CREATE POLICY "anon_delete_coas" ON coas FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- activity_log
-- ============================================================
CREATE TABLE IF NOT EXISTS activity_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  timestamp timestamptz DEFAULT now(),
  event_type text,
  source text DEFAULT 'system',
  message text,
  severity text DEFAULT 'info',
  related_id text
);

ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_activity_log" ON activity_log;
CREATE POLICY "anon_select_activity_log" ON activity_log FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_activity_log" ON activity_log;
CREATE POLICY "anon_insert_activity_log" ON activity_log FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_activity_log" ON activity_log;
CREATE POLICY "anon_update_activity_log" ON activity_log FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_activity_log" ON activity_log;
CREATE POLICY "anon_delete_activity_log" ON activity_log FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- briefings
-- ============================================================
CREATE TABLE IF NOT EXISTS briefings (
  id text PRIMARY KEY,
  title text,
  type text,
  status text DEFAULT 'draft',
  reference_id text,
  content_markdown text,
  sources jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE briefings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_briefings" ON briefings;
CREATE POLICY "anon_select_briefings" ON briefings FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_briefings" ON briefings;
CREATE POLICY "anon_insert_briefings" ON briefings FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_briefings" ON briefings;
CREATE POLICY "anon_update_briefings" ON briefings FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_briefings" ON briefings;
CREATE POLICY "anon_delete_briefings" ON briefings FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- exercises
-- ============================================================
CREATE TABLE IF NOT EXISTS exercises (
  id text PRIMARY KEY,
  name text,
  status text DEFAULT 'planning',
  assessment_summary text DEFAULT '',
  overall_score double precision,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_exercises" ON exercises;
CREATE POLICY "anon_select_exercises" ON exercises FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_exercises" ON exercises;
CREATE POLICY "anon_insert_exercises" ON exercises FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_exercises" ON exercises;
CREATE POLICY "anon_update_exercises" ON exercises FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_exercises" ON exercises;
CREATE POLICY "anon_delete_exercises" ON exercises FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- injects
-- ============================================================
CREATE TABLE IF NOT EXISTS injects (
  id text PRIMARY KEY,
  exercise_id text REFERENCES exercises(id),
  inject_type text,
  target_groups jsonb DEFAULT '[]'::jsonb,
  content text,
  scheduled_offset text DEFAULT '00:00',
  urgency text DEFAULT 'routine',
  status text DEFAULT 'pending',
  score double precision,
  assessment_notes text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE injects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_injects" ON injects;
CREATE POLICY "anon_select_injects" ON injects FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_injects" ON injects;
CREATE POLICY "anon_insert_injects" ON injects FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_injects" ON injects;
CREATE POLICY "anon_update_injects" ON injects FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_injects" ON injects;
CREATE POLICY "anon_delete_injects" ON injects FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- usage_events
-- ============================================================
CREATE TABLE IF NOT EXISTS usage_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  timestamp timestamptz NOT NULL DEFAULT now(),
  kind text NOT NULL,
  username text,
  feature text,
  path text,
  method text,
  status_code integer,
  latency_ms integer,
  client_ip text,
  detail text
);

CREATE INDEX IF NOT EXISTS idx_usage_timestamp ON usage_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_usage_kind ON usage_events(kind);
CREATE INDEX IF NOT EXISTS idx_usage_username ON usage_events(username);

ALTER TABLE usage_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_usage_events" ON usage_events;
CREATE POLICY "anon_select_usage_events" ON usage_events FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_usage_events" ON usage_events;
CREATE POLICY "anon_insert_usage_events" ON usage_events FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_usage_events" ON usage_events;
CREATE POLICY "anon_update_usage_events" ON usage_events FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_usage_events" ON usage_events;
CREATE POLICY "anon_delete_usage_events" ON usage_events FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- watchlist_items
-- ============================================================
CREATE TABLE IF NOT EXISTS watchlist_items (
  id text PRIMARY KEY,
  username text NOT NULL,
  label text NOT NULL,
  query text NOT NULL,
  entity_kind text NOT NULL,
  category text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_watchlist_username ON watchlist_items(username);
CREATE INDEX IF NOT EXISTS idx_watchlist_active ON watchlist_items(username, active);

ALTER TABLE watchlist_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_watchlist_items" ON watchlist_items;
CREATE POLICY "anon_select_watchlist_items" ON watchlist_items FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_watchlist_items" ON watchlist_items;
CREATE POLICY "anon_insert_watchlist_items" ON watchlist_items FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_watchlist_items" ON watchlist_items;
CREATE POLICY "anon_update_watchlist_items" ON watchlist_items FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_watchlist_items" ON watchlist_items;
CREATE POLICY "anon_delete_watchlist_items" ON watchlist_items FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- users (notification preferences)
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  username text PRIMARY KEY,
  email text,
  phone_number text,
  sms_enabled boolean DEFAULT false,
  email_enabled boolean DEFAULT false,
  timezone text DEFAULT 'America/New_York',
  created_at timestamptz DEFAULT now(),
  unsubscribed_at timestamptz
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_users" ON users;
CREATE POLICY "anon_select_users" ON users FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_users" ON users;
CREATE POLICY "anon_insert_users" ON users FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_users" ON users;
CREATE POLICY "anon_update_users" ON users FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_users" ON users;
CREATE POLICY "anon_delete_users" ON users FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- notification_log
-- ============================================================
CREATE TABLE IF NOT EXISTS notification_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username text NOT NULL REFERENCES users(username),
  channel text NOT NULL,
  card_id text,
  digest_week text,
  provider_message_id text,
  status text NOT NULL,
  error_text text,
  sent_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notif_log_user_channel_date ON notification_log(username, channel, sent_at);
CREATE INDEX IF NOT EXISTS idx_notif_log_card_dedupe ON notification_log(username, card_id) WHERE card_id IS NOT NULL;

ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_notification_log" ON notification_log;
CREATE POLICY "anon_select_notification_log" ON notification_log FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_notification_log" ON notification_log;
CREATE POLICY "anon_insert_notification_log" ON notification_log FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_notification_log" ON notification_log;
CREATE POLICY "anon_update_notification_log" ON notification_log FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_notification_log" ON notification_log;
CREATE POLICY "anon_delete_notification_log" ON notification_log FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- saved_entities (knowledge graph)
-- ============================================================
CREATE TABLE IF NOT EXISTS saved_entities (
  id text PRIMARY KEY,
  entity_id text NOT NULL UNIQUE,
  name text NOT NULL,
  entity_type text NOT NULL,
  country text,
  aliases jsonb DEFAULT '[]'::jsonb,
  identifiers jsonb DEFAULT '{}'::jsonb,
  notes text DEFAULT '',
  created_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_saved_entities_type ON saved_entities(entity_type);

ALTER TABLE saved_entities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_saved_entities" ON saved_entities;
CREATE POLICY "anon_select_saved_entities" ON saved_entities FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_saved_entities" ON saved_entities;
CREATE POLICY "anon_insert_saved_entities" ON saved_entities FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_saved_entities" ON saved_entities;
CREATE POLICY "anon_update_saved_entities" ON saved_entities FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_saved_entities" ON saved_entities;
CREATE POLICY "anon_delete_saved_entities" ON saved_entities FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- saved_edges (knowledge graph)
-- ============================================================
CREATE TABLE IF NOT EXISTS saved_edges (
  id text PRIMARY KEY,
  source_id text NOT NULL,
  target_id text NOT NULL,
  relationship_type text NOT NULL,
  properties jsonb DEFAULT '{}'::jsonb,
  confidence text DEFAULT 'MEDIUM',
  created_by text,
  created_at timestamptz DEFAULT now(),
  UNIQUE (source_id, target_id, relationship_type)
);

CREATE INDEX IF NOT EXISTS idx_saved_edges_source ON saved_edges(source_id);
CREATE INDEX IF NOT EXISTS idx_saved_edges_target ON saved_edges(target_id);

ALTER TABLE saved_edges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_saved_edges" ON saved_edges;
CREATE POLICY "anon_select_saved_edges" ON saved_edges FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_saved_edges" ON saved_edges;
CREATE POLICY "anon_insert_saved_edges" ON saved_edges FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_saved_edges" ON saved_edges;
CREATE POLICY "anon_update_saved_edges" ON saved_edges FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_saved_edges" ON saved_edges;
CREATE POLICY "anon_delete_saved_edges" ON saved_edges FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- priorities (team-wide collection priorities)
-- ============================================================
CREATE TABLE IF NOT EXISTS priorities (
  id text PRIMARY KEY,
  level text NOT NULL,
  key text NOT NULL,
  weight double precision NOT NULL DEFAULT 1.0,
  label text DEFAULT '',
  notes text DEFAULT '',
  created_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (level, key)
);

CREATE INDEX IF NOT EXISTS idx_priorities_level ON priorities(level);

ALTER TABLE priorities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_priorities" ON priorities;
CREATE POLICY "anon_select_priorities" ON priorities FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_priorities" ON priorities;
CREATE POLICY "anon_insert_priorities" ON priorities FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_priorities" ON priorities;
CREATE POLICY "anon_update_priorities" ON priorities FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_priorities" ON priorities;
CREATE POLICY "anon_delete_priorities" ON priorities FOR DELETE TO anon, authenticated USING (true);
