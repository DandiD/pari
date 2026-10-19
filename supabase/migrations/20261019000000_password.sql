-- Pari: password facoltativa per i gruppi
-- Un gruppo con password si apre solo con il link E la password. La password la imposta, cambia o toglie
-- solo chi ha creato il gruppo: il suo dispositivo ha una chiave da amministratore (qui ne salviamo solo l'hash).
-- Chi inserisce la password giusta riceve un token, derivato dall'hash della password: cambiando password,
-- tutti i token vecchi smettono di valere.
-- I gruppi creati prima di questa migrazione non hanno amministratore: il primo che imposta la password lo diventa.

alter table public.groups
  add column if not exists pass_hash  text,
  add column if not exists admin_hash text,
  add column if not exists failed     int not null default 0,
  add column if not exists failed_at  timestamptz;

create schema if not exists pari_private;
revoke all on schema pari_private from public, anon, authenticated;

create or replace function pari_private.token(p_group text, p_pass_hash text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_group || ':' || p_pass_hash, 'sha256'), 'hex');
$$;

-- Errore 'locked' se il gruppo ha una password e il token non è valido
create or replace function pari_private.check_access(p_group text, p_token text)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare v_hash text;
begin
  select pass_hash into v_hash from public.groups where id = p_group;
  if not found then raise exception 'group_not_found'; end if;
  if v_hash is not null and (p_token is null or p_token <> pari_private.token(p_group, v_hash)) then
    raise exception 'locked';
  end if;
end;
$$;

-- Errore 'not_admin' se il gruppo ha un amministratore e la chiave non corrisponde
create or replace function pari_private.check_admin(p_group text, p_admin text)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare v_admin text;
begin
  select admin_hash into v_admin from public.groups where id = p_group;
  if v_admin is not null and (p_admin is null or encode(extensions.digest(p_admin, 'sha256'), 'hex') <> v_admin) then
    raise exception 'not_admin';
  end if;
end;
$$;

-- Le firme cambiano: via le vecchie, così PostgREST non trova due versioni della stessa funzione
drop function if exists public.pari_get(text);
drop function if exists public.pari_save_group(text, text, jsonb, boolean);
drop function if exists public.pari_save_expense(text, text, jsonb);
drop function if exists public.pari_delete_expense(text, text);
drop function if exists public.pari_delete_group(text);

-- Lettura di un gruppo con tutte le spese. Gruppo protetto e token non valido: solo {"locked": true}
create or replace function public.pari_get(p_group text, p_token text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare g public.groups;
begin
  select * into g from public.groups where id = p_group;
  if not found then return null; end if;
  if g.pass_hash is not null and (p_token is null or p_token <> pari_private.token(g.id, g.pass_hash)) then
    return jsonb_build_object('locked', true);
  end if;
  return jsonb_build_object(
    'group', jsonb_build_object(
      'id', g.id, 'name', g.name, 'members', g.members, 'example', g.example,
      'private', g.pass_hash is not null, 'hasAdmin', g.admin_hash is not null,
      'updatedAt', (extract(epoch from g.updated_at) * 1000)::bigint),
    'expenses', coalesce(
      (select jsonb_agg(e.body || jsonb_build_object('id', e.id))
         from public.expenses e where e.group_id = g.id), '[]'::jsonb));
end;
$$;

-- Prova la password. Risponde {"token": ...}, {"error": "wrong_password"} o {"error": "too_many_attempts"}.
-- Non solleva eccezioni sui tentativi sbagliati, altrimenti il contatore verrebbe annullato.
create or replace function public.pari_unlock(p_group text, p_pass text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare g public.groups;
begin
  select * into g from public.groups where id = p_group for update;
  if not found then return jsonb_build_object('error', 'group_not_found'); end if;
  if g.pass_hash is null then return jsonb_build_object('token', null); end if;
  if g.failed >= 10 and g.failed_at > now() - interval '15 minutes' then
    return jsonb_build_object('error', 'too_many_attempts');
  end if;
  if p_pass is not null and extensions.crypt(p_pass, g.pass_hash) = g.pass_hash then
    update public.groups set failed = 0, failed_at = null where id = p_group;
    return jsonb_build_object('token', pari_private.token(g.id, g.pass_hash));
  end if;
  update public.groups
     set failed = case when failed_at is null or failed_at < now() - interval '15 minutes' then 1 else failed + 1 end,
         failed_at = now()
   where id = p_group;
  return jsonb_build_object('error', 'wrong_password');
end;
$$;

-- Crea o aggiorna un gruppo. Alla creazione, p_admin (se c'è) diventa la chiave da amministratore
create or replace function public.pari_save_group(p_group text, p_name text, p_members jsonb, p_example boolean default false,
  p_token text default null, p_admin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_group is null or char_length(p_group) < 20 then raise exception 'invalid_group'; end if;
  if jsonb_typeof(p_members) <> 'array' then raise exception 'invalid_members'; end if;
  if exists (select 1 from jsonb_array_elements(p_members) m
             where jsonb_typeof(m) <> 'object'
                or char_length(coalesce(m->>'id','')) not between 4 and 40
                or char_length(coalesce(m->>'name','')) > 40) then
    raise exception 'invalid_members';
  end if;
  if p_admin is not null and char_length(p_admin) < 20 then raise exception 'invalid_admin'; end if;
  if exists (select 1 from public.groups where id = p_group) then
    perform pari_private.check_access(p_group, p_token);
    update public.groups set name = trim(p_name), members = p_members, updated_at = now() where id = p_group;
  else
    insert into public.groups (id, name, members, example, admin_hash)
    values (p_group, trim(p_name), p_members, coalesce(p_example, false),
            case when p_admin is null then null else encode(extensions.digest(p_admin, 'sha256'), 'hex') end);
  end if;
end;
$$;

-- Imposta, cambia o toglie (p_new vuota o null) la password. Solo l'amministratore.
-- Gruppo senza amministratore (creato prima delle password): chi la imposta lo diventa con p_admin.
-- Restituisce il nuovo token (null se il gruppo torna aperto).
create or replace function public.pari_set_password(p_group text, p_token text, p_admin text, p_new text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_hash text;
begin
  perform pari_private.check_access(p_group, p_token);
  if p_admin is null or char_length(p_admin) < 20 then raise exception 'not_admin'; end if;
  perform pari_private.check_admin(p_group, p_admin);
  if p_new is not null and p_new <> '' and char_length(p_new) not between 4 and 72 then raise exception 'invalid_password'; end if;
  v_hash := case when p_new is null or p_new = '' then null else extensions.crypt(p_new, extensions.gen_salt('bf', 10)) end;
  update public.groups
     set pass_hash = v_hash, failed = 0, failed_at = null, updated_at = now(),
         admin_hash = coalesce(admin_hash, encode(extensions.digest(p_admin, 'sha256'), 'hex'))
   where id = p_group;
  return case when v_hash is null then null else pari_private.token(p_group, v_hash) end;
end;
$$;

-- Crea o aggiorna una spesa
create or replace function public.pari_save_expense(p_group text, p_id text, p_body jsonb, p_token text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
begin
  perform pari_private.check_access(p_group, p_token);
  if jsonb_typeof(p_body) <> 'object' then raise exception 'invalid_body'; end if;
  if jsonb_typeof(p_body->'amount') <> 'number' then raise exception 'invalid_amount'; end if;
  v_amount := (p_body->>'amount')::numeric;
  if v_amount <= 0 or v_amount > 100000000 or v_amount <> trunc(v_amount) then raise exception 'invalid_amount'; end if;
  if char_length(coalesce(p_body->>'title','')) > 120 then raise exception 'invalid_title'; end if;
  if (select count(*) from public.expenses where group_id = p_group) >= 3000
     and not exists (select 1 from public.expenses where group_id = p_group and id = p_id) then
    raise exception 'group_full';
  end if;
  insert into public.expenses (group_id, id, body)
  values (p_group, p_id, p_body - 'id')
  on conflict (group_id, id) do update set body = excluded.body, updated_at = now();
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

create or replace function public.pari_delete_expense(p_group text, p_id text, p_token text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pari_private.check_access(p_group, p_token);
  delete from public.expenses where group_id = p_group and id = p_id;
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

-- Elimina il gruppo: serve l'accesso e, se il gruppo ha un amministratore, la sua chiave
create or replace function public.pari_delete_group(p_group text, p_token text default null, p_admin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pari_private.check_access(p_group, p_token);
  perform pari_private.check_admin(p_group, p_admin);
  delete from public.groups where id = p_group;
end;
$$;

revoke execute on all functions in schema pari_private from public, anon, authenticated;

revoke execute on function public.pari_get(text, text), public.pari_unlock(text, text),
  public.pari_save_group(text, text, jsonb, boolean, text, text), public.pari_set_password(text, text, text, text),
  public.pari_save_expense(text, text, jsonb, text), public.pari_delete_expense(text, text, text),
  public.pari_delete_group(text, text, text) from public;
grant execute on function public.pari_get(text, text), public.pari_unlock(text, text),
  public.pari_save_group(text, text, jsonb, boolean, text, text), public.pari_set_password(text, text, text, text),
  public.pari_save_expense(text, text, jsonb, text), public.pari_delete_expense(text, text, text),
  public.pari_delete_group(text, text, text) to anon, authenticated;
