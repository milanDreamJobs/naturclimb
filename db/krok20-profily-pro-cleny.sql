-- krok20-profily-pro-cleny.sql
-- Clenove vidi profily ostatnich clenu - vsechno krome rodneho cisla.
-- Pohled bezi s pravy vlastnika tabulky (obchazi RLS tabulky), ale vrati radky jen
-- prihlasenemu aktivnimu clenovi a sloupec birth_number v nem vubec neni.
-- Tabulka member_profiles se nemeni: cely radek vc. RC dal vidi jen jeho majitel a admin.
-- Predpoklad: bezel krok19 a krok3 (is_club_member()).
-- V Supabase pustit jako jedno query; kazdy prikaz je schvalne na jednom radku,
-- bez diakritiky a bez CREATE TABLE (editor jinak skript rozsekne).

CREATE OR REPLACE VIEW public.member_profiles_club WITH (security_barrier = true) AS SELECT p.id, p.updated_at, p.avatar_url, p.belay_auto, p.belay_semi_auto, p.belay_tube, p.bio, p.chs_member, p.course_metodika, p.course_pady, p.course_zdravoveda, p.grade_sax_hi, p.grade_sax_lo, p.grade_uiaa_hi, p.grade_uiaa_lo, p.helmet_mountains, p.helmet_never, p.helmet_pisek, p.helmet_sport, p.insurance, p.is_chs_instructor, p.is_student, p.phone, p.preferred_areas, p.safety_alpine_s, p.safety_alpine_w, p.safety_basics, p.safety_firstaid, p.safety_pisek, p.safety_rescue, p.style_bezky, p.style_bezky_is_mentor, p.style_bezky_mentor, p.style_bezky_rating, p.style_boulder, p.style_boulder_is_mentor, p.style_boulder_mentor, p.style_boulder_rating, p.style_firstlead, p.style_firstlead_is_mentor, p.style_firstlead_mentor, p.style_firstlead_rating, p.style_ice, p.style_ice_is_mentor, p.style_ice_mentor, p.style_ice_rating, p.style_multipitch, p.style_multipitch_is_mentor, p.style_multipitch_mentor, p.style_multipitch_rating, p.style_pisek, p.style_pisek_is_mentor, p.style_pisek_mentor, p.style_pisek_rating, p.style_skialpy, p.style_skialpy_is_mentor, p.style_skialpy_mentor, p.style_skialpy_rating, p.style_sport, p.style_sport_is_mentor, p.style_sport_mentor, p.style_sport_rating, p.style_stena, p.style_stena_is_mentor, p.style_stena_mentor, p.style_stena_rating, p.style_toprope, p.style_toprope_is_mentor, p.style_toprope_mentor, p.style_toprope_rating, p.year_started FROM public.member_profiles p JOIN public.members m ON m.id = p.id AND coalesce(m.is_active, true) WHERE public.is_club_member();

REVOKE ALL ON public.member_profiles_club FROM anon, authenticated;
GRANT SELECT ON public.member_profiles_club TO authenticated;

-- Kontrola: cekame sloupcu = 71, ma_rc = false, prava = SELECT
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles_club') AS sloupcu, EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles_club' AND column_name = 'birth_number') AS ma_rc, (SELECT string_agg(privilege_type, ',') FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name = 'member_profiles_club' AND grantee = 'authenticated') AS prava;
