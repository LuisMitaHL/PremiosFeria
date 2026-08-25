-- ============================================================
-- PARTICIPANT AUTH MIGRATION — fixes audit finding F4
-- (no ownership check on p_participant_id; public UUIDs → impersonation)
-- ============================================================
-- Qué hace:
--   1. Vincula cada participante a un usuario de Supabase Auth vía
--      participants.auth_user_id (los nuevos registros usan
--      signInAnonymously desde el cliente: misma UX, identidad real).
--   2. Los RPC validate_and_scan y claim_reward ya no aceptan
--      p_participant_id: resuelven al participante por auth.uid().
--
-- Nota sobre participantes existentes: NO se aprovisionan usuarios de
-- Auth (no hay email ni forma de entregar credenciales a asistentes).
-- Quedan con auth_user_id NULL: visibles en el leaderboard, pero sin
-- posibilidad de escanear o canjear (deben registrarse de nuevo).
--
-- Requisito en el dashboard: Authentication > Sign In / Providers >
-- "Anonymous sign-ins" habilitado.
--
-- Idempotente: seguro de re-ejecutar. Ejecutar en el editor SQL de Supabase.
-- ============================================================

begin;

alter table public.participants
  add column if not exists auth_user_id uuid references auth.users(id);

create unique index if not exists participants_auth_user_id_key
  on public.participants(auth_user_id);

commit;
