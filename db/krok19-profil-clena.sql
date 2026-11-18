-- krok19-profil-clena.sql
-- Tabulka s lezeckým profilem každého člena.
-- Bezpečná degradace: pokud tabulka chybí, appka schová sekci Profil.
-- Idempotentní – lze spustit dvakrát bez chyby.

-- ============================================================
-- 1. Tabulka (CREATE IF NOT EXISTS – první spuštění)
-- ============================================================
CREATE TABLE IF NOT EXISTS member_profiles (
  id              text PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
  updated_at      timestamptz DEFAULT now(),

  -- Kontaktní a osobní údaje
  birth_number    text,
  phone           text,
  is_student      boolean DEFAULT false,

  -- Základní info
  year_started    int,
  bio             text,
  preferred_areas text,

  -- Pojištění a ČHS
  chs_member       boolean DEFAULT false,
  insurance        text CHECK (insurance IN ('none','chs_trio','alpenverein')) DEFAULT 'none',

  -- Jistění
  belay_tube       boolean DEFAULT false,
  belay_semi_auto  boolean DEFAULT false,
  belay_auto       boolean DEFAULT false,

  -- Lezu v přilbě
  helmet_never     boolean DEFAULT false,
  helmet_mountains boolean DEFAULT false,
  helmet_pisek     boolean DEFAULT false,
  helmet_sport     boolean DEFAULT false,

  -- Styl lezení: leze / preference (1-10) / chci mentora / jsem mentor
  style_firstlead           boolean DEFAULT false,
  style_firstlead_rating    smallint CHECK (style_firstlead_rating BETWEEN 1 AND 10),
  style_firstlead_mentor    boolean DEFAULT false,
  style_firstlead_is_mentor boolean DEFAULT false,

  style_toprope             boolean DEFAULT false,
  style_toprope_rating      smallint CHECK (style_toprope_rating BETWEEN 1 AND 10),
  style_toprope_mentor      boolean DEFAULT false,
  style_toprope_is_mentor   boolean DEFAULT false,

  style_pisek               boolean DEFAULT false,
  style_pisek_rating        smallint CHECK (style_pisek_rating BETWEEN 1 AND 10),
  style_pisek_mentor        boolean DEFAULT false,
  style_pisek_is_mentor     boolean DEFAULT false,

  style_boulder             boolean DEFAULT false,
  style_boulder_rating      smallint CHECK (style_boulder_rating BETWEEN 1 AND 10),
  style_boulder_mentor      boolean DEFAULT false,
  style_boulder_is_mentor   boolean DEFAULT false,

  style_sport               boolean DEFAULT false,
  style_sport_rating        smallint CHECK (style_sport_rating BETWEEN 1 AND 10),
  style_sport_mentor        boolean DEFAULT false,
  style_sport_is_mentor     boolean DEFAULT false,

  style_multipitch           boolean DEFAULT false,
  style_multipitch_rating    smallint CHECK (style_multipitch_rating BETWEEN 1 AND 10),
  style_multipitch_mentor    boolean DEFAULT false,
  style_multipitch_is_mentor boolean DEFAULT false,

  style_ice                 boolean DEFAULT false,
  style_ice_rating          smallint CHECK (style_ice_rating BETWEEN 1 AND 10),
  style_ice_mentor          boolean DEFAULT false,
  style_ice_is_mentor       boolean DEFAULT false,

  style_skialpy             boolean DEFAULT false,
  style_skialpy_rating      smallint CHECK (style_skialpy_rating BETWEEN 1 AND 10),
  style_skialpy_mentor      boolean DEFAULT false,
  style_skialpy_is_mentor   boolean DEFAULT false,

  style_bezky               boolean DEFAULT false,
  style_bezky_rating        smallint CHECK (style_bezky_rating BETWEEN 1 AND 10),
  style_bezky_mentor        boolean DEFAULT false,
  style_bezky_is_mentor     boolean DEFAULT false,

  -- Obtížnost — thermometry range (lo/hi)
  grade_uiaa_lo text,
  grade_uiaa_hi text,
  grade_sax_lo  text,
  grade_sax_hi  text,

  -- Sebehodnocení znalostí bezpečnosti (1-10)
  safety_basics   smallint CHECK (safety_basics BETWEEN 1 AND 10),
  safety_pisek    smallint CHECK (safety_pisek BETWEEN 1 AND 10),
  safety_alpine_s smallint CHECK (safety_alpine_s BETWEEN 1 AND 10),
  safety_alpine_w smallint CHECK (safety_alpine_w BETWEEN 1 AND 10),
  safety_rescue   smallint CHECK (safety_rescue BETWEEN 1 AND 10),
  safety_firstaid smallint CHECK (safety_firstaid BETWEEN 1 AND 10),

  avatar_url text
);

-- ============================================================
-- 1b. ALTER TABLE — idempotentní přidání nových sloupců
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_skialpy') THEN
    ALTER TABLE member_profiles ADD COLUMN style_skialpy boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_skialpy_rating') THEN
    ALTER TABLE member_profiles ADD COLUMN style_skialpy_rating smallint CHECK (style_skialpy_rating BETWEEN 1 AND 10);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_skialpy_mentor') THEN
    ALTER TABLE member_profiles ADD COLUMN style_skialpy_mentor boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_skialpy_is_mentor') THEN
    ALTER TABLE member_profiles ADD COLUMN style_skialpy_is_mentor boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_bezky') THEN
    ALTER TABLE member_profiles ADD COLUMN style_bezky boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_bezky_rating') THEN
    ALTER TABLE member_profiles ADD COLUMN style_bezky_rating smallint CHECK (style_bezky_rating BETWEEN 1 AND 10);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_bezky_mentor') THEN
    ALTER TABLE member_profiles ADD COLUMN style_bezky_mentor boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='style_bezky_is_mentor') THEN
    ALTER TABLE member_profiles ADD COLUMN style_bezky_is_mentor boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='grade_uiaa_lo') THEN
    ALTER TABLE member_profiles ADD COLUMN grade_uiaa_lo text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='grade_uiaa_hi') THEN
    ALTER TABLE member_profiles ADD COLUMN grade_uiaa_hi text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='grade_sax_lo') THEN
    ALTER TABLE member_profiles ADD COLUMN grade_sax_lo text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='member_profiles' AND column_name='grade_sax_hi') THEN
    ALTER TABLE member_profiles ADD COLUMN grade_sax_hi text;
  END IF;
END $$;

-- ============================================================
-- 2. Trigger: updated_at automaticky
-- ============================================================
CREATE OR REPLACE FUNCTION set_member_profile_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_profiles_updated_at ON member_profiles;
CREATE TRIGGER trg_member_profiles_updated_at
  BEFORE UPDATE ON member_profiles
  FOR EACH ROW EXECUTE FUNCTION set_member_profile_updated_at();

-- ============================================================
-- 3. RLS
-- ============================================================
ALTER TABLE member_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS member_profiles_select_own ON member_profiles;
CREATE POLICY member_profiles_select_own ON member_profiles
  FOR SELECT USING (
    id = (SELECT id FROM members WHERE email = auth.email())
    OR
    EXISTS (SELECT 1 FROM members WHERE email = auth.email() AND is_admin = true)
  );

DROP POLICY IF EXISTS member_profiles_insert_own ON member_profiles;
CREATE POLICY member_profiles_insert_own ON member_profiles
  FOR INSERT WITH CHECK (
    id = (SELECT id FROM members WHERE email = auth.email())
  );

DROP POLICY IF EXISTS member_profiles_update_own ON member_profiles;
CREATE POLICY member_profiles_update_own ON member_profiles
  FOR UPDATE USING (
    id = (SELECT id FROM members WHERE email = auth.email())
  );
