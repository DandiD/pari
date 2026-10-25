-- Pari: la home mostra quante persone ci sono in ogni gruppo, anche in quelli privati.
-- Dei privati resta nascosto chi sono: arriva solo il numero.

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
      'memberCount', jsonb_array_length(g.members),
      'updatedAt', (extract(epoch from g.updated_at) * 1000)::bigint)
    order by g.updated_at desc), '[]'::jsonb)
  from public.groups g
  where not g.example;
$$;
