-- krok21-gdpr-souhlas.sql
-- Souhlas clena s evidenci osobnich udaju dle GDPR (+ kdy ho udelil).
-- Vidi ho jen clen sam a admin (pohled member_profiles_club ho neobsahuje).
-- Idempotentni. Kazdy prikaz na jednom radku, bez diakritiky (editor v Supabase jinak skript rozsekne).

ALTER TABLE public.member_profiles ADD COLUMN IF NOT EXISTS gdpr_consent boolean DEFAULT false, ADD COLUMN IF NOT EXISTS gdpr_consent_at timestamptz;

-- Kontrola: cekame sloupcu = 2, v_pohledu = 0
SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles' AND column_name IN ('gdpr_consent','gdpr_consent_at')) AS sloupcu, (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'member_profiles_club' AND column_name LIKE 'gdpr%') AS v_pohledu;
