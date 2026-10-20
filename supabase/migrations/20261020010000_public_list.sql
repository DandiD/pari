-- Pari: tutti i gruppi sono visibili nella home.
-- pari_list restituisce l'elenco; un gruppo privato aperto senza password risponde comunque con il nome.
-- Spese e partecipanti dei gruppi privati restano dietro la password.

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
    return jsonb_build_object('locked', true, 'name', g.name);
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

-- Elenco pubblico di tutti i gruppi, per la home. I gruppi di esempio no.
-- Gruppi aperti: nome e partecipanti (chi entra li vede comunque). Gruppi privati: solo il nome.
create or replace function public.pari_list()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id, 'name', g.name, 'private', g.pass_hash is not null, 'hasAdmin', g.admin_hash is not null,
      'members', case when g.pass_hash is null then g.members else '[]'::jsonb end,
      'updatedAt', (extract(epoch from g.updated_at) * 1000)::bigint)
    order by g.updated_at desc), '[]'::jsonb)
  from public.groups g
  where not g.example;
$$;

revoke execute on function public.pari_list() from public;
grant execute on function public.pari_list() to anon, authenticated;
