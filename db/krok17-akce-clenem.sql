-- Krok 17: Člen může navrhnout akci
-- Přidá dva sloupce do tabulky events:
--   created_by_member  ... kdo akci navrhl (null = admin), typ TEXT (stejný jako members.id)
--   is_draft           ... true = čeká na schválení adminem

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS created_by_member text REFERENCES members(id),
  ADD COLUMN IF NOT EXISTS is_draft boolean DEFAULT false;

-- Ověření:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'events' AND column_name IN ('created_by_member', 'is_draft');
