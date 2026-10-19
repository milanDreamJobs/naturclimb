-- ============================================================
-- NaturClimb - kontrola: prihlasky s nevyplnenym poctem noci
-- ============================================================
-- Kam: Supabase -> SQL Editor -> New query -> vlozit -> Run
-- Nic nemeni, jen se diva.
--
-- Proc: appka donedavna ukladala "0 noci" jako prazdnou hodnotu (NULL).
-- NULL ale znamena "pouzij delku akce", takze se takovemu cloveku
-- pri zuctovani naúčtovaly noci, ktere nespal.
--
-- Co s vysledkem: komu v seznamu dole sedi "nejspis spal 0 noci"
-- (ma zvyhodnene noci, ale plne nevyplnene), tomu nastav nulu:
--   update public.event_registrations set nights = 0 where id = '<id radku>';
-- ============================================================

select r.id,
       e.name                                   as akce,
       m.name                                   as clen,
       r.nights                                 as plne_noci,
       r.nights_reduced                         as zvyhodnene_noci,
       case when r.nights is null and coalesce(r.nights_reduced, 0) > 0
            then 'nejspis spal 0 plnych noci'
            when r.nights is null
            then 'nevyplneno - pocita se delka akce'
            else 'ok'
       end                                      as poznamka,
       r.settled_at is not null                 as vyuctoval_se_sam,
       r.settled_amount,
       e.status                                 as stav_akce
  from public.event_registrations r
  join public.events  e on e.id = r.event_id
  join public.members m on m.id = r.member_id
 where r.nights is null
 order by e.start_datetime desc, m.name;
