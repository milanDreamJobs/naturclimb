-- Krok 17: Člen může navrhnout akci
-- Přidá dva sloupce do tabulky events:
--   created_by_member  ... kdo akci navrhl (null = admin)
--   is_draft           ... true = čeká na schválení adminem

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS created_by_member uuid REFERENCES members(id),
  ADD COLUMN IF NOT EXISTS is_draft boolean DEFAULT false;

-- RLS: Draft vidí jen autor a admini
-- Stávající politika SELECT na events by měla být rozšířena:
-- (Je-li is_draft = true, vidí ji jen created_by_member nebo admin.)
-- Pokud nemáš RLS na events zapnuté, stačí aplikační logika v index.html.

-- Ověření:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'events' AND column_name IN ('created_by_member', 'is_draft');
