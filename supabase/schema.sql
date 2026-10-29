-- ============================================================================
-- BARANGAY SAFETY INCIDENT REPORTING APPLICATION
-- Complete Supabase Database Schema
-- Run this entire file in the Supabase SQL Editor (Dashboard → SQL Editor)
-- ============================================================================

-- Enable PostGIS for spatial queries (already available on Supabase)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. BARANGAYS TABLE (reference data for the 5 pilot barangays)
-- ============================================================================
CREATE TABLE IF NOT EXISTS barangays (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL UNIQUE,
  center_lat DOUBLE PRECISION NOT NULL,
  center_lng DOUBLE PRECISION NOT NULL,
  description TEXT,
  population INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the 5 pilot barangays
-- Surveyed on site 2026-08-25. The original values here were development
-- placeholders 293-745m out, and findNearestBarangay() routes non-resident
-- emergencies off these columns: three of the five halls resolved to the WRONG
-- barangay when standing at their own front door. See
-- migration_2026_08_25_real_barangay_coordinates.sql.
INSERT INTO barangays (name, center_lat, center_lng, description) VALUES
  ('Barangay 1',  13.941946, 121.157097, 'High-density urban barangay in Lipa City'),
  ('Barangay 2',  13.943443, 121.158837, 'High-density urban barangay in Lipa City'),
  ('Barangay 3',  13.943112, 121.160564, 'High-density urban barangay in Lipa City'),
  ('Barangay 7',  13.936218, 121.160714, 'High-density urban barangay in Lipa City'),
  ('Barangay 10', 13.942557, 121.167828, 'High-density urban barangay in Lipa City')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 2. PROFILES TABLE (extends Supabase auth.users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS profiles (
  id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             TEXT NOT NULL,
  full_name         TEXT NOT NULL,
  phone             TEXT NOT NULL,
  role              TEXT NOT NULL DEFAULT 'resident'
                      CHECK (role IN ('superadmin', 'admin', 'resident', 'non_resident')),
  barangay_id       UUID REFERENCES barangays(id),
  address           TEXT,
  profile_photo_url TEXT,
  id_photo_url      TEXT,
  is_verified       BOOLEAN NOT NULL DEFAULT FALSE,
  is_locked         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_profiles_barangay ON profiles(barangay_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- ============================================================================
-- 3. INCIDENTS TABLE (core reporting data)
-- ============================================================================
CREATE TABLE IF NOT EXISTS incidents (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporter_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  barangay_id      UUID NOT NULL REFERENCES barangays(id),
  category         TEXT NOT NULL,
  description      TEXT NOT NULL,
  severity_level   INTEGER NOT NULL CHECK (severity_level BETWEEN 1 AND 4),
  status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'in_progress', 'resolved', 'flagged')),
  latitude         DOUBLE PRECISION NOT NULL,
  longitude        DOUBLE PRECISION NOT NULL,
  address          TEXT,
  assigned_to      UUID REFERENCES profiles(id),
  resolution_notes TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at      TIMESTAMPTZ,
  -- PostGIS geography column for spatial queries
  location         GEOGRAPHY(Point, 4326)
);

-- Auto-populate the geography column from lat/lng
CREATE OR REPLACE FUNCTION set_incident_location()
RETURNS TRIGGER AS $$
BEGIN
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_incident_location
  BEFORE INSERT OR UPDATE ON incidents
  FOR EACH ROW
  EXECUTE FUNCTION set_incident_location();

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_incidents_barangay ON incidents(barangay_id);
CREATE INDEX IF NOT EXISTS idx_incidents_reporter ON incidents(reporter_id);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_severity ON incidents(severity_level);
CREATE INDEX IF NOT EXISTS idx_incidents_created ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_location ON incidents USING GIST(location);

-- ============================================================================
-- 4. INCIDENT MEDIA TABLE (photo attachments)
-- ============================================================================
CREATE TABLE IF NOT EXISTS incident_media (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  photo_url   TEXT NOT NULL,
  file_name   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_media_incident ON incident_media(incident_id);

-- ============================================================================
-- 5. AUDIT LOGS TABLE (tracks all official actions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  incident_id UUID REFERENCES incidents(id) ON DELETE SET NULL,
  details     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_incident ON audit_logs(incident_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at DESC);

-- ============================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE barangays ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE incident_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ── Helper function: get current user's role ────────────────────────────
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ── Helper function: get current user's barangay ────────────────────────
CREATE OR REPLACE FUNCTION get_user_barangay()
RETURNS UUID AS $$
  SELECT barangay_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ── BARANGAYS: readable by all authenticated users ──────────────────────
CREATE POLICY "Barangays are viewable by all authenticated users"
  ON barangays FOR SELECT
  TO authenticated
  USING (true);

-- ── PROFILES ────────────────────────────────────────────────────────────

-- Users can read their own profile
CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- Officials can view profiles in their barangay
CREATE POLICY "Officials can view barangay profiles"
  ON profiles FOR SELECT
  TO authenticated
  USING (
    get_user_role() IN ('admin', 'superadmin')
    AND (
      get_user_role() = 'superadmin'
      OR barangay_id = get_user_barangay()
    )
  );

-- Users can insert their own profile (during registration)
CREATE POLICY "Users can create own profile"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid());

-- Officials can update profiles in their barangay (verify, lock, etc.)
CREATE POLICY "Officials can update barangay profiles"
  ON profiles FOR UPDATE
  TO authenticated
  USING (
    get_user_role() IN ('admin', 'superadmin')
    AND (
      get_user_role() = 'superadmin'
      OR barangay_id = get_user_barangay()
    )
  );

-- ── INCIDENTS ───────────────────────────────────────────────────────────

-- Residents can view their own incidents
CREATE POLICY "Residents can view own incidents"
  ON incidents FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

-- Officials can view incidents in their barangay
CREATE POLICY "Officials can view barangay incidents"
  ON incidents FOR SELECT
  TO authenticated
  USING (
    get_user_role() IN ('admin', 'superadmin')
    AND (
      get_user_role() = 'superadmin'
      OR barangay_id = get_user_barangay()
    )
  );

-- Authenticated users can create incidents
CREATE POLICY "Authenticated users can create incidents"
  ON incidents FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- Officials can update incidents in their barangay
CREATE POLICY "Officials can update barangay incidents"
  ON incidents FOR UPDATE
  TO authenticated
  USING (
    get_user_role() IN ('admin', 'superadmin')
    AND (
      get_user_role() = 'superadmin'
      OR barangay_id = get_user_barangay()
    )
  );

-- Superadmin can delete incidents
CREATE POLICY "Superadmin can delete incidents"
  ON incidents FOR DELETE
  TO authenticated
  USING (get_user_role() = 'superadmin');

-- ── INCIDENT MEDIA ──────────────────────────────────────────────────────

-- Anyone who can view the incident can view its media
CREATE POLICY "Users can view incident media"
  ON incident_media FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM incidents
      WHERE incidents.id = incident_media.incident_id
        AND (
          incidents.reporter_id = auth.uid()
          OR get_user_role() IN ('admin', 'superadmin')
        )
    )
  );

-- Authenticated users can upload media to their own incidents
CREATE POLICY "Users can upload incident media"
  ON incident_media FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM incidents
      WHERE incidents.id = incident_media.incident_id
        AND incidents.reporter_id = auth.uid()
    )
  );

-- ── AUDIT LOGS ──────────────────────────────────────────────────────────

-- Officials can view audit logs
CREATE POLICY "Officials can view audit logs"
  ON audit_logs FOR SELECT
  TO authenticated
  USING (get_user_role() IN ('admin', 'superadmin'));

-- Officials can create audit logs
CREATE POLICY "Officials can create audit logs"
  ON audit_logs FOR INSERT
  TO authenticated
  WITH CHECK (
    get_user_role() IN ('admin', 'superadmin')
    AND user_id = auth.uid()
  );

-- ============================================================================
-- 7. STORAGE BUCKETS (run these via Supabase Dashboard or SQL)
-- ============================================================================
-- Note: Storage bucket creation is typically done via the Supabase Dashboard.
-- Go to Storage → New Bucket and create:
--   1. "incident-photos"  (public: true)
--   2. "profile-photos"   (public: true)
--   3. "id-verification"  (public: false)

-- Storage policies (run in SQL Editor after creating buckets):

-- Allow authenticated users to upload to incident-photos
INSERT INTO storage.policies (name, bucket_id, operation, definition, check_expression)
SELECT
  'Allow authenticated uploads',
  'incident-photos',
  'INSERT',
  '(auth.role() = ''authenticated'')',
  '(auth.role() = ''authenticated'')'
WHERE NOT EXISTS (
  SELECT 1 FROM storage.policies
  WHERE name = 'Allow authenticated uploads' AND bucket_id = 'incident-photos'
);

-- Allow public read access to incident-photos
INSERT INTO storage.policies (name, bucket_id, operation, definition)
SELECT
  'Allow public read',
  'incident-photos',
  'SELECT',
  '(true)'
WHERE NOT EXISTS (
  SELECT 1 FROM storage.policies
  WHERE name = 'Allow public read' AND bucket_id = 'incident-photos'
);

-- ============================================================================
-- 8. USEFUL DATABASE FUNCTIONS
-- ============================================================================

-- Get incidents within a radius (in meters) of a point
CREATE OR REPLACE FUNCTION get_nearby_incidents(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_radius_meters DOUBLE PRECISION DEFAULT 1000
)
RETURNS SETOF incidents AS $$
  SELECT *
  FROM incidents
  WHERE ST_DWithin(
    location,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_meters
  )
  ORDER BY created_at DESC;
$$ LANGUAGE sql STABLE;

-- Get incident counts grouped by barangay
CREATE OR REPLACE FUNCTION get_barangay_incident_counts()
RETURNS TABLE(barangay_id UUID, barangay_name TEXT, total BIGINT, pending BIGINT, in_progress BIGINT, resolved BIGINT) AS $$
  SELECT
    b.id AS barangay_id,
    b.name AS barangay_name,
    COUNT(i.id) AS total,
    COUNT(i.id) FILTER (WHERE i.status = 'pending') AS pending,
    COUNT(i.id) FILTER (WHERE i.status = 'in_progress') AS in_progress,
    COUNT(i.id) FILTER (WHERE i.status = 'resolved') AS resolved
  FROM barangays b
  LEFT JOIN incidents i ON i.barangay_id = b.id
  GROUP BY b.id, b.name
  ORDER BY b.name;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 9. SEED A SUPERADMIN (run after you sign up your first admin user)
-- ============================================================================
-- After registering via the app, update the first user to superadmin:
--
--   UPDATE profiles
--   SET role = 'superadmin', is_verified = true
--   WHERE email = 'your-admin-email@example.com';
--
-- ============================================================================

-- Done! Your database is ready.
