-- ================================================================
-- MIGRATION: Add landmark to incidents + media_type to incident_media
-- Run this in Supabase SQL Editor BEFORE testing the new report form.
-- Safe to run multiple times (uses IF NOT EXISTS).
-- ================================================================

-- 1. Add optional landmark column to incidents
ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS landmark TEXT;

-- 2. Add media_type column to incident_media (defaults to 'photo' for old rows)
ALTER TABLE incident_media
  ADD COLUMN IF NOT EXISTS media_type TEXT NOT NULL DEFAULT 'photo'
    CHECK (media_type IN ('photo', 'video'));

-- 3. Index for filtering media by type (optional, helps perf)
CREATE INDEX IF NOT EXISTS idx_incident_media_type
  ON incident_media (incident_id, media_type);

-- ================================================================
-- Verify
-- ================================================================
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'incidents' AND column_name = 'landmark';

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'incident_media' AND column_name = 'media_type';
