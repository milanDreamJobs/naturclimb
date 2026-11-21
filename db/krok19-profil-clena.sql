-- krok19-profil-clena.sql
-- Lezecky profil clena (tabulka member_profiles).
-- Bezpecna degradace: dokud tohle nebezi, appka sekci Profil schova.
-- Idempotentni - lze spustit opakovane (i kdyz uz starsi verze bezela).
-- Predpoklad: bezel krok3 (funkce current_member_id() a is_club_admin()).

-- !!! V Supabase SQL Editoru POUSTET VE DVOU KROCICH (dve samostatna query):
-- !!!   CAST 1 = jen CREATE TABLE, CAST 2 = vse ostatni.
-- !!! Kdyz je CREATE TABLE ve stejnem query jako dalsi prikazy, editor vklada
-- !!! vlastni "ENABLE ROW LEVEL SECURITY" a nasledujici prikaz uskne.

-- ============================================================
-- CAST 1 / 1. Tabulka (prvni spusteni)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.member_profiles (
  id              text PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
  updated_at      timestamptz DEFAULT now()
);

-- ============================================================
-- CAST 2 (samostatne query) / 2. Sloupce - pridaji se jen ty, ktere chybi
--    (funguje stejne na prazdne tabulce i na starsi verzi krok19)
--    Bez bloku DO a bez diakritiky - editor v Supabase jinak skript rozsekne.
-- ============================================================
ALTER TABLE public.member_profiles
  -- Osobni udaje
  ADD COLUMN IF NOT EXISTS birth_number               text,
  ADD COLUMN IF NOT EXISTS phone                      text,
  ADD COLUMN IF NOT EXISTS is_student                 boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_chs_instructor          boolean DEFAULT false,
  -- Zakladni info
  ADD COLUMN IF NOT EXISTS year_started               int,
  ADD COLUMN IF NOT EXISTS bio                        text,
  ADD COLUMN IF NOT EXISTS preferred_areas            text,
  -- CHS a pojisteni
  ADD COLUMN IF NOT EXISTS chs_member                 boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS insurance                  text DEFAULT 'none' CHECK (insurance IN ('none','chs_trio','alpenverein')),
  -- Jisteni
  ADD COLUMN IF NOT EXISTS belay_tube                 boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS belay_semi_auto            boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS belay_auto                 boolean DEFAULT false,
  -- Prilba
  ADD COLUMN IF NOT EXISTS helmet_never               boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS helmet_mountains           boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS helmet_pisek               boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS helmet_sport               boolean DEFAULT false,
  -- Absolvovane kurzy
  ADD COLUMN IF NOT EXISTS course_zdravoveda          boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS course_metodika            boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS course_pady                boolean DEFAULT false,
  -- Obtiznost - rozsah od/do
  ADD COLUMN IF NOT EXISTS grade_uiaa_lo              text,
  ADD COLUMN IF NOT EXISTS grade_uiaa_hi              text,
  ADD COLUMN IF NOT EXISTS grade_sax_lo               text,
  ADD COLUMN IF NOT EXISTS grade_sax_hi               text,
  -- Sebehodnoceni bezpecnosti 1-10
  ADD COLUMN IF NOT EXISTS safety_basics              smallint CHECK (safety_basics BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS safety_pisek               smallint CHECK (safety_pisek BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS safety_alpine_s            smallint CHECK (safety_alpine_s BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS safety_alpine_w            smallint CHECK (safety_alpine_w BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS safety_rescue              smallint CHECK (safety_rescue BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS safety_firstaid            smallint CHECK (safety_firstaid BETWEEN 1 AND 10),
  -- Styly lezeni: leze / preference 1-10 / chci mentora / jsem mentor
  ADD COLUMN IF NOT EXISTS style_firstlead            boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_firstlead_rating     smallint CHECK (style_firstlead_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_firstlead_mentor     boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_firstlead_is_mentor  boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_toprope              boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_toprope_rating       smallint CHECK (style_toprope_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_toprope_mentor       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_toprope_is_mentor    boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_pisek                boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_pisek_rating         smallint CHECK (style_pisek_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_pisek_mentor         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_pisek_is_mentor      boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_boulder              boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_boulder_rating       smallint CHECK (style_boulder_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_boulder_mentor       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_boulder_is_mentor    boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_sport                boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_sport_rating         smallint CHECK (style_sport_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_sport_mentor         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_sport_is_mentor      boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_multipitch           boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_multipitch_rating    smallint CHECK (style_multipitch_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_multipitch_mentor    boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_multipitch_is_mentor boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_stena                boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_stena_rating         smallint CHECK (style_stena_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_stena_mentor         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_stena_is_mentor      boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_ice                  boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_ice_rating           smallint CHECK (style_ice_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_ice_mentor           boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_ice_is_mentor        boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_skialpy              boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_skialpy_rating       smallint CHECK (style_skialpy_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_skialpy_mentor       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_skialpy_is_mentor    boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_bezky                boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_bezky_rating         smallint CHECK (style_bezky_rating BETWEEN 1 AND 10),
  ADD COLUMN IF NOT EXISTS style_bezky_mentor         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS style_bezky_is_mentor      boolean DEFAULT false,
  -- Fotka (faze 2)
  ADD COLUMN IF NOT EXISTS avatar_url                 text;

-- ============================================================
-- 3. updated_at se nastavi sam pri kazde zmene
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_member_profile_updated_at()
RETURNS trigger LANGUAGE plpgsql
AS 'BEGIN NEW.updated_at := now(); RETURN NEW; END;';

DROP TRIGGER IF EXISTS trg_member_profiles_updated_at ON public.member_profiles;
CREATE TRIGGER trg_member_profiles_updated_at
  BEFORE INSERT OR UPDATE ON public.member_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_member_profile_updated_at();

-- ============================================================
-- 4. Pravidla (RLS)
--    Clen cte a pise jen svuj radek, admin cte vsechny.
--    Nikdo nemaze (radek zmizi jen se smazanim clena).
-- ============================================================
ALTER TABLE public.member_profiles ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.member_profiles FROM anon;
GRANT SELECT, INSERT, UPDATE ON public.member_profiles TO authenticated;

DROP POLICY IF EXISTS member_profiles_select_own ON public.member_profiles;
CREATE POLICY member_profiles_select_own ON public.member_profiles
  FOR SELECT TO authenticated
  USING (id = public.current_member_id() OR public.is_club_admin());

DROP POLICY IF EXISTS member_profiles_insert_own ON public.member_profiles;
CREATE POLICY member_profiles_insert_own ON public.member_profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = public.current_member_id());

DROP POLICY IF EXISTS member_profiles_update_own ON public.member_profiles;
CREATE POLICY member_profiles_update_own ON public.member_profiles
  FOR UPDATE TO authenticated
  USING (id = public.current_member_id())
  WITH CHECK (id = public.current_member_id());

-- ============================================================
-- 5. Kontrola - vysledek vloz zpet do chatu
--    Cekame: sloupcu = 72, pravidla = 3, rls_zapnute = true
-- ============================================================
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'member_profiles'
       AND column_name IN (
         'id','updated_at','birth_number','phone','is_student','is_chs_instructor',
         'year_started','bio','preferred_areas','chs_member','insurance',
         'belay_tube','belay_semi_auto','belay_auto',
         'helmet_never','helmet_mountains','helmet_pisek','helmet_sport',
         'course_zdravoveda','course_metodika','course_pady',
         'grade_uiaa_lo','grade_uiaa_hi','grade_sax_lo','grade_sax_hi',
         'safety_basics','safety_pisek','safety_alpine_s','safety_alpine_w',
         'safety_rescue','safety_firstaid','avatar_url')
       OR (table_schema = 'public' AND table_name = 'member_profiles'
           AND column_name ~ '^style_(firstlead|toprope|pisek|boulder|sport|multipitch|stena|ice|skialpy|bezky)(_rating|_mentor|_is_mentor)?$')
  ) AS sloupcu,
  (SELECT count(*) FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'member_profiles') AS pravidla,
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.member_profiles'::regclass) AS rls_zapnute;
