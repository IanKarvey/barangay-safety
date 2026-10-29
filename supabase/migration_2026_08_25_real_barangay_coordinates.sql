-- ============================================================================
-- Replace seeded barangay centres with surveyed ground truth.
-- 2026-08-25
-- ============================================================================
--
-- ## Where these came from
--
-- The owner physically visited each of the five barangay halls and recorded
-- the GPS reading on site. These are measurements, not estimates, and they
-- supersede both the original development seeds and the OpenStreetMap
-- candidates that were sourced on 2026-08-18.
--
--   Barangay 1   Lipa City Library Hub, B. Morada Street, Poblacion
--   Barangay 2   unnamed road, Poblacion
--   Barangay 3   Rizal Street, Poblacion
--   Barangay 7   Cadena Street, Poblacion
--   Barangay 10  San Vicente Street, Poblacion
--
-- ## Why this mattered more than "the pin is slightly off"
--
-- `BarangayService.findNearestBarangay()` decides which barangay hall receives
-- a non-resident emergency, by haversine against these very columns. The seeds
-- were 293–745 m out.
--
-- Checked against the surveyed positions: standing at a real barangay hall,
-- the seeded data routed the emergency to the WRONG barangay in **three cases
-- out of five**.
--
--   at Barangay 1  -> seeds answered Barangay 3
--   at Barangay 3  -> seeds answered Barangay 2
--   at Barangay 7  -> seeds answered Barangay 3
--
-- With the surveyed values all five resolve to themselves. The halls sit as
-- little as 190 m apart (Barangay 2 to Barangay 3), which is why a few hundred
-- metres of error was enough to send help to the wrong hall.
--
-- The OSM candidates would have been an improvement but not a fix: Barangay 7
-- was still 230 m off and Barangay 3 134 m off. Those hardcoded candidates are
-- now replaced by these in barangay_coordinates_screen.dart.
--
-- Safe to run more than once — it sets absolute values.
-- ============================================================================

UPDATE public.barangays SET center_lat = 13.941946, center_lng = 121.157097
WHERE name = 'Barangay 1';

UPDATE public.barangays SET center_lat = 13.943443, center_lng = 121.158837
WHERE name = 'Barangay 2';

UPDATE public.barangays SET center_lat = 13.943112, center_lng = 121.160564
WHERE name = 'Barangay 3';

UPDATE public.barangays SET center_lat = 13.936218, center_lng = 121.160714
WHERE name = 'Barangay 7';

UPDATE public.barangays SET center_lat = 13.942557, center_lng = 121.167828
WHERE name = 'Barangay 10';


-- ============================================================================
-- Verification
-- ============================================================================

-- 1. Expect all five to match the values above exactly.
SELECT name, center_lat, center_lng
FROM   public.barangays
ORDER  BY name;

-- 2. Nothing left on a seed value. Expect zero rows.
--    (The seeds were all 4-decimal; the surveyed values are 6-decimal.)
SELECT name, center_lat, center_lng
FROM   public.barangays
WHERE  (center_lat, center_lng) IN (
         (13.9420, 121.1640),
         (13.9435, 121.1620),
         (13.9400, 121.1610),
         (13.9390, 121.1650),
         (13.9445, 121.1660)
       );

-- 3. Routing self-check: for each barangay, the nearest centre should be
--    itself. Expect `nearest` to equal `name` on all five rows. Any row where
--    they differ means an emergency raised at that hall would be sent to a
--    different one.
SELECT b.name,
       (SELECT o.name
        FROM   public.barangays o
        ORDER  BY (o.center_lat - b.center_lat) ^ 2
                + (o.center_lng - b.center_lng) ^ 2
        LIMIT  1) AS nearest
FROM   public.barangays b
ORDER  BY b.name;
