-- =========================================================================
-- ADMIN AUTH MIGRATION — fixes audit finding F2
-- (admin credentials publicly readable & overwritable)
--
-- What it does:
--   1. Links every community to a Supabase Auth (GoTrue) user.
--   2. Drops the plaintext `password` column — login moves to Supabase Auth.
--   3. Replaces the world-writable communities_update policy with one
--      scoped to the owning admin (`auth_user_id = auth.uid()`).
--
-- After running:
--   - Authentication > Users in the Supabase dashboard: send each community
--     a password-reset/invite email. The seeded passwords are random and
--     unknowable — nobody can log in until a reset is completed.
--   - Deploy the matching client changes (src/lib/api.js admin functions).
--
-- WARNING: step 2 is destructive (the plaintext column is removed).
-- Snapshot the table first if you need the old values.
-- Safe to re-run (idempotent).
-- =========================================================================

begin;

create extension if not exists pgcrypto;

-- 1) Link column ---------------------------------------------------------
alter table public.communities
  add column if not exists auth_user_id uuid references auth.users(id);
create unique index if not exists communities_auth_user_id_key
  on public.communities(auth_user_id);

-- 2) Provision one GoTrue user per community -----------------------------
do $$
declare
  c record;
  uid uuid;
  v_email text;
begin
  for c in
    select id, username from public.communities where auth_user_id is null
  loop
    v_email := case
      when c.username like '%@%' then c.username
      else c.username || '@feria.local'
    end;

    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated', 'authenticated',
      lower(v_email),
      -- unguessable random password: log-in impossible until the organizer
      -- triggers a password reset from the dashboard
      crypt(gen_random_uuid()::text, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      '{}',
      now(), now()
    )
    on conflict (email) do nothing;

    select id into uid from auth.users where email = lower(v_email);

    insert into auth.identities (
      provider_id, id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      uid::text, uid, uid,
      format('{"sub":"%s","email":"%s"}', uid, lower(v_email))::jsonb,
      'email', now(), now(), now()
    )
    on conflict do nothing;

    update public.communities set auth_user_id = uid where id = c.id;
  end loop;
end $$;

-- 3) Remove plaintext credentials ----------------------------------------
alter table public.communities drop column if exists password;

-- 4) Scope UPDATE to the owning admin ------------------------------------
drop policy if exists "communities_update" on public.communities;
create policy "communities_update" on public.communities
  for update
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

commit;
