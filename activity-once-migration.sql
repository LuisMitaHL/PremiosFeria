-- ============================================================
-- ACTIVITY ONCE MIGRATION — fixes audit finding F7
-- (activity scans unlimited: no cooldown, no uniqueness)
-- ============================================================
-- Qué hace: las actividades pasan a ser una sola vez por stand y
-- participante, vía índice único parcial. Las visitas siguen siendo
-- repetibles tras su cooldown de 5 minutos (el índice no las cubre).
-- validate_and_scan ya rechaza duplicados con un mensaje amigable;
-- el índice es la puerta real contra carruras concurrentes.
--
-- ATENCIÓN: si tu base ya tiene actividades duplicadas del mismo
-- participante en el mismo stand, el CREATE INDEX falla. Revisa los
-- duplicados y decide antes de ejecutar (borrar scans NO ajusta los
-- puntos ya acreditados):
--
--   SELECT participant_id, community_id, count(*), min(created_at)
--   FROM scans WHERE type = 'activity'
--   GROUP BY 1, 2 HAVING count(*) > 1;
--
-- Idempotente: seguro de re-ejecutar. Ejecutar en el editor SQL de Supabase.
-- ============================================================

create unique index if not exists scans_one_activity_per_stand
  on public.scans (participant_id, community_id) where (type = 'activity');
