-- Pari: solo chi ha inserito una spesa può modificarla o eliminarla
-- Non ci sono account: ogni dispositivo ha una chiave segreta (in localStorage) e ogni spesa salva l'hash
-- di gruppo + chiave di chi l'ha creata. L'amministratore del gruppo può comunque modificare ed eliminare tutto,
-- così una spesa non resta bloccata se chi l'ha inserita cambia telefono.
-- Le spese inserite prima di questa migrazione non hanno autore e restano modificabili da tutti.
-- Compatibile con la pagina vecchia: senza p_author le spese nuove nascono senza autore.

alter table public.expenses add column if not exists author_hash text;

create or replace function pari_private.author_hash(p_group text, p_author text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_group || ':' || p_author, 'sha256'), 'hex');
$$;

-- Errore 'not_author' se la spesa ha un autore e non sei né lui né l'amministratore del gruppo
create or replace function pari_private.check_author(p_group text, p_id text, p_author text, p_admin text)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare v_author text; v_admin text;
begin
  select author_hash into v_author from public.expenses where group_id = p_group and id = p_id;
  if v_author is null then return; end if;
  if p_author is not null and pari_private.author_hash(p_group, p_author) = v_author then return; end if;
  select admin_hash into v_admin from public.groups where id = p_group;
  if v_admin is not null and p_admin is not null and encode(extensions.digest(p_admin, 'sha256'), 'hex') = v_admin then return; end if;
  raise exception 'not_author';
end;
$$;

drop function if exists public.pari_get(text, text);
drop function if exists public.pari_save_expense(text, text, jsonb, text);
drop function if exists public.pari_delete_expense(text, text, text);

-- Come prima, ma ogni spesa porta anche "author" (l'hash, null per le spese senza autore):
-- la pagina lo confronta con il proprio per sapere quali spese può modificare
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
      (select jsonb_agg(e.body || jsonb_build_object('id', e.id, 'author', e.author_hash))
         from public.expenses e where e.group_id = g.id), '[]'::jsonb));
end;
$$;

-- Crea o aggiorna una spesa. Alla creazione p_author ne diventa l'autore; per modificarla serve la stessa chiave
-- (o quella da amministratore)
create or replace function public.pari_save_expense(p_group text, p_id text, p_body jsonb, p_token text default null,
  p_author text default null, p_admin text default null)
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
  if p_author is not null and char_length(p_author) < 20 then raise exception 'invalid_author'; end if;
  if (select count(*) from public.expenses where group_id = p_group) >= 3000
     and not exists (select 1 from public.expenses where group_id = p_group and id = p_id) then
    raise exception 'group_full';
  end if;
  perform pari_private.check_author(p_group, p_id, p_author, p_admin);
  insert into public.expenses (group_id, id, body, author_hash)
  values (p_group, p_id, p_body - 'id' - 'author',
          case when p_author is null then null else pari_private.author_hash(p_group, p_author) end)
  on conflict (group_id, id) do update set body = excluded.body, updated_at = now();
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

create or replace function public.pari_delete_expense(p_group text, p_id text, p_token text default null,
  p_author text default null, p_admin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pari_private.check_access(p_group, p_token);
  perform pari_private.check_author(p_group, p_id, p_author, p_admin);
  delete from public.expenses where group_id = p_group and id = p_id;
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

revoke execute on all functions in schema pari_private from public, anon, authenticated;

revoke execute on function public.pari_get(text, text),
  public.pari_save_expense(text, text, jsonb, text, text, text),
  public.pari_delete_expense(text, text, text, text, text) from public;
grant execute on function public.pari_get(text, text),
  public.pari_save_expense(text, text, jsonb, text, text, text),
  public.pari_delete_expense(text, text, text, text, text) to anon, authenticated;
