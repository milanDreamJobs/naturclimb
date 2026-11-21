-- krok21-datum-narozeni-a-gdpr.sql
-- 1) Datum narozeni misto rodneho cisla (vidi ho jen clen sam a admin).
-- 2) Souhlas clena s evidenci osobnich udaju dle GDPR (+ kdy ho udelil).
-- 3) Uz zadana rodna cisla se prevedou na datum narozeni a pak se SMAZOU
--    (sloupec birth_number zustava prazdny, appka ho uz nepouziva).
-- Pohled member_profiles_club tyto sloupce neobsahuje - ostatni clenove je neuvidi.
-- Idempotentni. Kazdy prikaz na jednom radku, bez diakritiky (editor v Supabase jinak skript rozsekne).

ALTER TABLE public.member_profiles ADD COLUMN IF NOT EXISTS birth_date date, ADD COLUMN IF NOT EXISTS gdpr_consent boolean DEFAULT false, ADD COLUMN IF NOT EXISTS gdpr_consent_at timestamptz;

UPDATE public.member_profiles p SET birth_date = x.dt FROM (SELECT id, d, make_date(y, m, 1) + (d - 1) AS dt FROM (SELECT id, CASE WHEN length(r) = 9 OR substr(r, 1, 2)::int >= 54 THEN 1900 ELSE 2000 END + substr(r, 1, 2)::int AS y, CASE WHEN substr(r, 3, 2)::int > 70 THEN substr(r, 3, 2)::int - 70 WHEN substr(r, 3, 2)::int > 50 THEN substr(r, 3, 2)::int - 50 WHEN substr(r, 3, 2)::int > 20 THEN substr(r, 3, 2)::int - 20 ELSE substr(r, 3, 2)::int END AS m, substr(r, 5, 2)::int AS d FROM (SELECT id, regexp_replace(birth_number, '[^0-9]', '', 'g') AS r FROM public.member_profiles WHERE birth_number IS NOT NULL) a WHERE length(r) IN (9, 10)) b WHERE m BETWEEN 1 AND 12 AND d BETWEEN 1 AND 31) x WHERE p.id = x.id AND p.birth_date IS NULL AND extract(day FROM x.dt) = x.d AND x.dt <= current_date;

UPDATE public.member_profiles SET birth_number = NULL WHERE birth_number IS NOT NULL;

-- Kontrola: cekame sloupcu = 3, rc_zbyva = 0, v_pohledu = 0 (s_datem = kolik clenu ma datum narozeni)
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles' AND column_name IN ('birth_date','gdpr_consent','gdpr_consent_at')) AS sloupcu, (SELECT count(*) FROM public.member_profiles WHERE birth_date IS NOT NULL) AS s_datem, (SELECT count(*) FROM public.member_profiles WHERE birth_number IS NOT NULL) AS rc_zbyva, (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles_club' AND (column_name LIKE 'gdpr%' OR column_name LIKE 'birth%')) AS v_pohledu;
