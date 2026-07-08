/*
# Create Wargame Simulation Tables

Creates the full wargame simulation schema including country agents, scenarios,
simulations, events, and vector-backed agent memory. Mirrors the Alembic
migrations 0001-0004 from the wargame backend.

1. Extensions
  - `vector` (pgvector) - For agent memory embeddings
  - `uuid-ossp` - For UUID generation

2. Enum Types
  - `relationship_posture` - allied/friendly/neutral/tense/hostile
  - `data_source_status` - active/degraded/disabled
  - `event_domain` - info/diplomatic/economic/cyber/kinetic_limited/kinetic_general
  - `scenario_status` - draft/ready/archived
  - `simulation_status` - pending/running/paused/completed/aborted/error
  - `memory_type` - observation/decision/intel/doctrine

3. New Tables
  - `wg_countries` - Master registry of country agents with doctrine and profiles
    - `id` (uuid, primary key, auto-generated)
    - `iso3` (text, unique, not null) - ISO 3166-1 alpha-3 code
    - `name` (text, not null)
    - `profile` (jsonb) - Country profile data
    - `doctrine` (jsonb) - Military/economic doctrine
    - `red_lines` (jsonb) - Array of red lines that trigger escalation
    - `military_assets` (jsonb) - Military capability summary
    - `persona` (text) - Leadership persona markdown
    - `gdp_usd` (numeric) - GDP in USD
    - `created_at` / `updated_at` (timestamptz)

  - `wg_relationships` - Bilateral relationship state between country pairs
    - `id` (uuid, primary key)
    - `country_a_id` / `country_b_id` (uuid, FK to wg_countries)
    - `posture` (relationship_posture enum)
    - `trust_score` (integer, -100 to 100)
    - `alliance_memberships` (jsonb) - Array of alliance names
    - `updated_at` (timestamptz)
    - UNIQUE(country_a_id, country_b_id)

  - `wg_data_sources` - Registry of data ingestion sources
    - `id` (uuid, primary key)
    - `source_key` (text, unique) - Machine identifier
    - `display_name` (text)
    - `last_ingest_at` (timestamptz)
    - `status` (data_source_status enum)
    - `records_ingested` (integer)
    - `metadata` (jsonb)
    - `created_at` (timestamptz)

  - `wg_events` - Raw normalized events from data lake
    - `id` (uuid, primary key)
    - `data_source_id` (uuid, FK to wg_data_sources)
    - `source` (text) - Source identifier
    - `occurred_at` (timestamptz) - When event happened
    - `actor_iso3` / `target_iso3` (text) - Actor and target countries
    - `event_type` (text)
    - `domain` (event_domain enum)
    - `severity` (numeric)
    - `payload` (jsonb) - Full event data
    - `raw_text` (text) - Original text
    - `ingested_at` (timestamptz)

  - `wg_scenarios` - User-authored what-if prompts
    - `id` (uuid, primary key)
    - `title` (text, not null)
    - `description` (text)
    - `country_ids` (jsonb) - Array of participating country UUIDs
    - `initial_conditions` (jsonb)
    - `status` (scenario_status enum)
    - `created_at` / `updated_at` (timestamptz)

  - `wg_simulations` - Execution runs of scenarios
    - `id` (uuid, primary key)
    - `scenario_id` (uuid, FK to wg_scenarios, CASCADE)
    - `status` (simulation_status enum)
    - `current_turn` (integer, default 0)
    - `max_turns` (integer, default 20)
    - `world_state_snapshot` (jsonb) - Current world state
    - `config` (jsonb) - Run configuration
    - `started_at` / `completed_at` / `created_at` (timestamptz)

  - `wg_sim_events` - Actions taken by country agents during simulation
    - `id` (uuid, primary key)
    - `sim_id` (uuid, FK to wg_simulations, CASCADE)
    - `parent_event_id` (uuid, self-FK) - Escalation chain tree
    - `turn` (integer)
    - `actor_country` (text) - ISO3 of acting country
    - `target_country` (text) - ISO3 of target
    - `domain` (event_domain enum)
    - `action_type` (text)
    - `payload` (jsonb) - Action details
    - `rationale` (text) - Agent reasoning
    - `citations` (jsonb) - Source citations array
    - `escalation_rung` (integer, 0-5)
    - `explainability` (jsonb) - Structured explanation triplet
    - `timestamp` (timestamptz)

  - `wg_agent_memory` - Per-country episodic memory with vector embeddings
    - `id` (uuid, primary key)
    - `sim_id` (uuid, FK to wg_simulations, CASCADE)
    - `country_iso3` (text)
    - `content` (text) - Memory text
    - `embedding` (vector(1536)) - Voyage-3 embedding for RAG
    - `memory_type` (memory_type enum)
    - `turn` (integer)
    - `metadata` (jsonb)
    - `created_at` (timestamptz)

  - `wg_ais_positions` - Live AIS vessel position buffer
    - `id` (bigint, auto-increment)
    - `mmsi` (varchar(16))
    - `latitude` / `longitude` (double precision)
    - `speed` / `course` (double precision, nullable)
    - `timestamp` (timestamptz)
    - `ingested_at` (timestamptz)

4. Security
  - RLS enabled on ALL tables.
  - Permissive policies for anon+authenticated (backend mediates access).

5. Important Notes
  - Tables prefixed with `wg_` to avoid conflicts with Emissary core tables.
  - The `wg_agent_memory` table uses pgvector HNSW index for fast similarity search.
  - The `wg_sim_events` table has a self-referential FK for escalation chains.
  - GIN indexes on all JSONB columns for containment queries.
*/

-- ============================================================
-- Extensions
-- ============================================================
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- Enum types (idempotent via DO block)
-- ============================================================
DO $$ BEGIN
  CREATE TYPE relationship_posture AS ENUM ('allied', 'friendly', 'neutral', 'tense', 'hostile');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE data_source_status AS ENUM ('active', 'degraded', 'disabled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE event_domain AS ENUM ('info', 'diplomatic', 'economic', 'cyber', 'kinetic_limited', 'kinetic_general');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE scenario_status AS ENUM ('draft', 'ready', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE simulation_status AS ENUM ('pending', 'running', 'paused', 'completed', 'aborted', 'error');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE memory_type AS ENUM ('observation', 'decision', 'intel', 'doctrine');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- wg_countries
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_countries (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  iso3 text NOT NULL,
  name text NOT NULL,
  profile jsonb NOT NULL DEFAULT '{}'::jsonb,
  doctrine jsonb NOT NULL DEFAULT '{}'::jsonb,
  red_lines jsonb NOT NULL DEFAULT '[]'::jsonb,
  military_assets jsonb NOT NULL DEFAULT '{}'::jsonb,
  persona text,
  gdp_usd numeric(20, 2),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ix_wg_countries_iso3 ON wg_countries(iso3);
CREATE INDEX IF NOT EXISTS ix_wg_countries_profile_gin ON wg_countries USING gin(profile);
CREATE INDEX IF NOT EXISTS ix_wg_countries_doctrine_gin ON wg_countries USING gin(doctrine);

ALTER TABLE wg_countries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_countries" ON wg_countries;
CREATE POLICY "anon_select_wg_countries" ON wg_countries FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_countries" ON wg_countries;
CREATE POLICY "anon_insert_wg_countries" ON wg_countries FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_countries" ON wg_countries;
CREATE POLICY "anon_update_wg_countries" ON wg_countries FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_countries" ON wg_countries;
CREATE POLICY "anon_delete_wg_countries" ON wg_countries FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_relationships
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_relationships (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_a_id uuid NOT NULL REFERENCES wg_countries(id) ON DELETE CASCADE,
  country_b_id uuid NOT NULL REFERENCES wg_countries(id) ON DELETE CASCADE,
  posture relationship_posture NOT NULL DEFAULT 'neutral',
  trust_score integer NOT NULL DEFAULT 0 CHECK (trust_score BETWEEN -100 AND 100),
  alliance_memberships jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (country_a_id, country_b_id)
);

CREATE INDEX IF NOT EXISTS ix_wg_relationships_country_a ON wg_relationships(country_a_id);
CREATE INDEX IF NOT EXISTS ix_wg_relationships_country_b ON wg_relationships(country_b_id);

ALTER TABLE wg_relationships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_relationships" ON wg_relationships;
CREATE POLICY "anon_select_wg_relationships" ON wg_relationships FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_relationships" ON wg_relationships;
CREATE POLICY "anon_insert_wg_relationships" ON wg_relationships FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_relationships" ON wg_relationships;
CREATE POLICY "anon_update_wg_relationships" ON wg_relationships FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_relationships" ON wg_relationships;
CREATE POLICY "anon_delete_wg_relationships" ON wg_relationships FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_data_sources
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_data_sources (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  source_key text NOT NULL,
  display_name text NOT NULL,
  last_ingest_at timestamptz,
  status data_source_status NOT NULL DEFAULT 'active',
  records_ingested integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ix_wg_data_sources_source_key ON wg_data_sources(source_key);

ALTER TABLE wg_data_sources ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_data_sources" ON wg_data_sources;
CREATE POLICY "anon_select_wg_data_sources" ON wg_data_sources FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_data_sources" ON wg_data_sources;
CREATE POLICY "anon_insert_wg_data_sources" ON wg_data_sources FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_data_sources" ON wg_data_sources;
CREATE POLICY "anon_update_wg_data_sources" ON wg_data_sources FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_data_sources" ON wg_data_sources;
CREATE POLICY "anon_delete_wg_data_sources" ON wg_data_sources FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_events
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  data_source_id uuid REFERENCES wg_data_sources(id) ON DELETE SET NULL,
  source text NOT NULL,
  occurred_at timestamptz NOT NULL,
  actor_iso3 text,
  target_iso3 text,
  event_type text,
  domain event_domain,
  severity numeric(5, 2),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_text text,
  ingested_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_events_source_occurred_at ON wg_events(source, occurred_at);
CREATE INDEX IF NOT EXISTS ix_wg_events_payload_gin ON wg_events USING gin(payload);
CREATE INDEX IF NOT EXISTS ix_wg_events_actor_target ON wg_events(actor_iso3, target_iso3);
CREATE INDEX IF NOT EXISTS ix_wg_events_data_source_id ON wg_events(data_source_id);
CREATE INDEX IF NOT EXISTS ix_wg_events_domain ON wg_events(domain);

ALTER TABLE wg_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_events" ON wg_events;
CREATE POLICY "anon_select_wg_events" ON wg_events FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_events" ON wg_events;
CREATE POLICY "anon_insert_wg_events" ON wg_events FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_events" ON wg_events;
CREATE POLICY "anon_update_wg_events" ON wg_events FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_events" ON wg_events;
CREATE POLICY "anon_delete_wg_events" ON wg_events FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_scenarios
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_scenarios (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  country_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  initial_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
  status scenario_status NOT NULL DEFAULT 'ready',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_scenarios_status ON wg_scenarios(status);

ALTER TABLE wg_scenarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_scenarios" ON wg_scenarios;
CREATE POLICY "anon_select_wg_scenarios" ON wg_scenarios FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_scenarios" ON wg_scenarios;
CREATE POLICY "anon_insert_wg_scenarios" ON wg_scenarios FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_scenarios" ON wg_scenarios;
CREATE POLICY "anon_update_wg_scenarios" ON wg_scenarios FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_scenarios" ON wg_scenarios;
CREATE POLICY "anon_delete_wg_scenarios" ON wg_scenarios FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_simulations
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_simulations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  scenario_id uuid NOT NULL REFERENCES wg_scenarios(id) ON DELETE CASCADE,
  status simulation_status NOT NULL DEFAULT 'pending',
  current_turn integer NOT NULL DEFAULT 0,
  max_turns integer NOT NULL DEFAULT 20,
  world_state_snapshot jsonb,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_simulations_scenario_id ON wg_simulations(scenario_id);
CREATE INDEX IF NOT EXISTS ix_wg_simulations_status ON wg_simulations(status);

ALTER TABLE wg_simulations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_simulations" ON wg_simulations;
CREATE POLICY "anon_select_wg_simulations" ON wg_simulations FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_simulations" ON wg_simulations;
CREATE POLICY "anon_insert_wg_simulations" ON wg_simulations FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_simulations" ON wg_simulations;
CREATE POLICY "anon_update_wg_simulations" ON wg_simulations FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_simulations" ON wg_simulations;
CREATE POLICY "anon_delete_wg_simulations" ON wg_simulations FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_sim_events
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_sim_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sim_id uuid NOT NULL REFERENCES wg_simulations(id) ON DELETE CASCADE,
  parent_event_id uuid REFERENCES wg_sim_events(id) ON DELETE SET NULL,
  turn integer NOT NULL,
  actor_country text NOT NULL,
  target_country text,
  domain event_domain NOT NULL,
  action_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  rationale text NOT NULL DEFAULT '',
  citations jsonb NOT NULL DEFAULT '[]'::jsonb,
  escalation_rung integer NOT NULL DEFAULT 0,
  explainability jsonb,
  timestamp timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_sim_events_sim_turn ON wg_sim_events(sim_id, turn);
CREATE INDEX IF NOT EXISTS ix_wg_sim_events_actor_domain ON wg_sim_events(actor_country, domain);
CREATE INDEX IF NOT EXISTS ix_wg_sim_events_parent_event_id ON wg_sim_events(parent_event_id);
CREATE INDEX IF NOT EXISTS ix_wg_sim_events_payload_gin ON wg_sim_events USING gin(payload);

ALTER TABLE wg_sim_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_sim_events" ON wg_sim_events;
CREATE POLICY "anon_select_wg_sim_events" ON wg_sim_events FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_sim_events" ON wg_sim_events;
CREATE POLICY "anon_insert_wg_sim_events" ON wg_sim_events FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_sim_events" ON wg_sim_events;
CREATE POLICY "anon_update_wg_sim_events" ON wg_sim_events FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_sim_events" ON wg_sim_events;
CREATE POLICY "anon_delete_wg_sim_events" ON wg_sim_events FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_agent_memory (with vector embeddings)
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_agent_memory (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sim_id uuid NOT NULL REFERENCES wg_simulations(id) ON DELETE CASCADE,
  country_iso3 text NOT NULL,
  content text NOT NULL,
  embedding vector(1536) NOT NULL,
  memory_type memory_type NOT NULL DEFAULT 'observation',
  turn integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_agent_memory_sim_country ON wg_agent_memory(sim_id, country_iso3);
CREATE INDEX IF NOT EXISTS ix_wg_agent_memory_embedding_hnsw ON wg_agent_memory
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

ALTER TABLE wg_agent_memory ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_agent_memory" ON wg_agent_memory;
CREATE POLICY "anon_select_wg_agent_memory" ON wg_agent_memory FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_agent_memory" ON wg_agent_memory;
CREATE POLICY "anon_insert_wg_agent_memory" ON wg_agent_memory FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_agent_memory" ON wg_agent_memory;
CREATE POLICY "anon_update_wg_agent_memory" ON wg_agent_memory FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_agent_memory" ON wg_agent_memory;
CREATE POLICY "anon_delete_wg_agent_memory" ON wg_agent_memory FOR DELETE TO anon, authenticated USING (true);

-- ============================================================
-- wg_ais_positions (vessel tracking buffer)
-- ============================================================
CREATE TABLE IF NOT EXISTS wg_ais_positions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mmsi varchar(16) NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  speed double precision,
  course double precision,
  timestamp timestamptz NOT NULL,
  ingested_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_wg_ais_positions_mmsi_timestamp ON wg_ais_positions(mmsi, timestamp DESC);
CREATE INDEX IF NOT EXISTS ix_wg_ais_positions_timestamp ON wg_ais_positions(timestamp);

ALTER TABLE wg_ais_positions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_wg_ais_positions" ON wg_ais_positions;
CREATE POLICY "anon_select_wg_ais_positions" ON wg_ais_positions FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_wg_ais_positions" ON wg_ais_positions;
CREATE POLICY "anon_insert_wg_ais_positions" ON wg_ais_positions FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_wg_ais_positions" ON wg_ais_positions;
CREATE POLICY "anon_update_wg_ais_positions" ON wg_ais_positions FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_wg_ais_positions" ON wg_ais_positions;
CREATE POLICY "anon_delete_wg_ais_positions" ON wg_ais_positions FOR DELETE TO anon, authenticated USING (true);
