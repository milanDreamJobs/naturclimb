-- krok19-profil-clena.sql
-- Lezecký profil člena (tabulka member_profiles).
-- Bezpečná degradace: dokud tohle neběží, appka sekci Profil schová.
-- Idempotentní – lze spustit opakovaně (i když už starší verze běžela).
-- Předpoklad: běžel krok3 (funkce current_member_id() a is_club_admin()).

-- ============================================================
-- 1. Tabulka (první spuštění)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.member_profiles (
  id              text PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
  updated_at      timestamptz DEFAULT now()
);

-- ============================================================
-- 2. Sloupce – přidají se jen ty, které chybí
--    (funguje stejně na prázdné tabulce i na starší verzi krok19)
-- ============================================================
DO $$
DECLARE
  sloupce text[][] := ARRAY[
    -- Osobní údaje
    ['birth_number',      'text'],
    ['phone',             'text'],
    ['is_student',        'boolean DEFAULT false'],
    ['is_chs_instructor', 'boolean DEFAULT false'],
    -- Základní info
    ['year_started',      'int'],
    ['bio',               'text'],
    ['preferred_areas',   'text'],
    -- ČHS a pojištění
    ['chs_member',        'boolean DEFAULT false'],
    ['insurance',         'text DEFAULT ''none'' CHECK (insurance IN (''none'',''chs_trio'',''alpenverein''))'],
    -- Jistění
    ['belay_tube',        'boolean DEFAULT false'],
    ['belay_semi_auto',   'boolean DEFAULT false'],
    ['belay_auto',        'boolean DEFAULT false'],
    -- Přilba
    ['helmet_never',      'boolean DEFAULT false'],
    ['helmet_mountains',  'boolean DEFAULT false'],
    ['helmet_pisek',      'boolean DEFAULT false'],
    ['helmet_sport',      'boolean DEFAULT false'],
    -- Absolvované kurzy
    ['course_zdravoveda', 'boolean DEFAULT false'],
    ['course_metodika',   'boolean DEFAULT false'],
    ['course_pady',       'boolean DEFAULT false'],
    -- Obtížnost – rozsah od/do
    ['grade_uiaa_lo',     'text'],
    ['grade_uiaa_hi',     'text'],
    ['grade_sax_lo',      'text'],
    ['grade_sax_hi',      'text'],
    -- Sebehodnocení bezpečnosti 1–10
    ['safety_basics',     'smallint CHECK (safety_basics BETWEEN 1 AND 10)'],
    ['safety_pisek',      'smallint CHECK (safety_pisek BETWEEN 1 AND 10)'],
    ['safety_alpine_s',   'smallint CHECK (safety_alpine_s BETWEEN 1 AND 10)'],
    ['safety_alpine_w',   'smallint CHECK (safety_alpine_w BETWEEN 1 AND 10)'],
    ['safety_rescue',     'smallint CHECK (safety_rescue BETWEEN 1 AND 10)'],
    ['safety_firstaid',   'smallint CHECK (safety_firstaid BETWEEN 1 AND 10)'],
    -- Fotka (fáze 2)
    ['avatar_url',        'text']
  ];
  styly text[] := ARRAY['firstlead','toprope','pisek','boulder','sport',
                        'multipitch','stena','ice','skialpy','bezky'];
  s text;
  i int;
BEGIN
  -- Styly lezení: leze / preference 1–10 / chci mentora / jsem mentor
  FOREACH s IN ARRAY styly LOOP
    sloupce := sloupce || ARRAY[
      ['style_' || s,                'boolean DEFAULT false'],
      ['style_' || s || '_rating',   format('smallint CHECK (%I BETWEEN 1 AND 10)', 'style_' || s || '_rating')],
      ['style_' || s || '_mentor',   'boolean DEFAULT false'],
      ['style_' || s || '_is_mentor','boolean DEFAULT false']
    ];
  END LOOP;

  FOR i IN 1 .. array_length(sloupce, 1) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'member_profiles'
         AND column_name = sloupce[i][1]
    ) THEN
      EXECUTE format('ALTER TABLE public.member_profiles ADD COLUMN %I %s',
                     sloupce[i][1], sloupce[i][2]);
      RAISE NOTICE 'pridan sloupec %', sloupce[i][1];
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 3. updated_at se nastaví sám při každé změně
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_member_profile_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_profiles_updated_at ON public.member_profiles;
CREATE TRIGGER trg_member_profiles_updated_at
  BEFORE INSERT OR UPDATE ON public.member_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_member_profile_updated_at();

-- ============================================================
-- 4. Pravidla (RLS)
--    Člen čte a píše jen svůj řádek, admin čte všechny.
--    Nikdo nemaže (řádek zmizí jen se smazáním člena).
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
-- 5. Kontrola – výsledek vlož zpět do chatu
--    Čekáme: sloupcu = 72, pravidla = 3, rls_zapnute = true
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
