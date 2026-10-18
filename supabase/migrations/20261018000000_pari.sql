-- Pari: schema per Supabase
-- Accesso senza account: chi conosce l'id segreto del gruppo (nel link) può leggere e scrivere quel gruppo.
-- Le tabelle non sono leggibili direttamente: tutto passa da funzioni che richiedono l'id del gruppo.

create table if not exists public.groups (
  id          text primary key check (char_length(id) between 20 and 64),
  name        text not null check (char_length(name) between 1 and 80),
  members     jsonb not null default '[]'::jsonb
              check (jsonb_typeof(members) = 'array' and jsonb_array_length(members) <= 40),
  example     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.expenses (
  group_id    text not null references public.groups(id) on delete cascade,
  id          text not null check (char_length(id) between 4 and 40),
  body        jsonb not null check (jsonb_typeof(body) = 'object' and pg_column_size(body) < 8000),
  updated_at  timestamptz not null default now(),
  primary key (group_id, id)
);

alter table public.groups   enable row level security;
alter table public.expenses enable row level security;
-- Nessuna policy: anon e authenticated non leggono né scrivono le tabelle direttamente.
revoke all on public.groups, public.expenses from anon, authenticated;

-- Lettura di un gruppo con tutte le spese
create or replace function public.pari_get(p_group text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'group', jsonb_build_object(
      'id', g.id, 'name', g.name, 'members', g.members, 'example', g.example,
      'updatedAt', (extract(epoch from g.updated_at) * 1000)::bigint),
    'expenses', coalesce(
      (select jsonb_agg(e.body || jsonb_build_object('id', e.id))
         from public.expenses e where e.group_id = g.id), '[]'::jsonb))
  from public.groups g
  where g.id = p_group;
$$;

-- Crea o aggiorna un gruppo
create or replace function public.pari_save_group(p_group text, p_name text, p_members jsonb, p_example boolean default false)
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
  insert into public.groups (id, name, members, example)
  values (p_group, trim(p_name), p_members, coalesce(p_example, false))
  on conflict (id) do update
    set name = excluded.name, members = excluded.members, updated_at = now();
end;
$$;

-- Crea o aggiorna una spesa
create or replace function public.pari_save_expense(p_group text, p_id text, p_body jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
begin
  if not exists (select 1 from public.groups where id = p_group) then raise exception 'group_not_found'; end if;
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

create or replace function public.pari_delete_expense(p_group text, p_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.expenses where group_id = p_group and id = p_id;
  update public.groups set updated_at = now() where id = p_group;
$$;

create or replace function public.pari_delete_group(p_group text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.groups where id = p_group;
$$;

revoke execute on function public.pari_get(text), public.pari_save_group(text, text, jsonb, boolean),
  public.pari_save_expense(text, text, jsonb), public.pari_delete_expense(text, text),
  public.pari_delete_group(text) from public;
grant execute on function public.pari_get(text), public.pari_save_group(text, text, jsonb, boolean),
  public.pari_save_expense(text, text, jsonb), public.pari_delete_expense(text, text),
  public.pari_delete_group(text) to anon, authenticated;
