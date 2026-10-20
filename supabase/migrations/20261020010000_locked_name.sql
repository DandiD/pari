-- Pari: un gruppo privato aperto senza password risponde anche con il nome,
-- così la pagina lo mette comunque in "I tuoi gruppi" (con il tag Privato) invece di farlo sparire.
-- Il nome lo vede solo chi ha già il link; spese e partecipanti restano dietro la password.

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
