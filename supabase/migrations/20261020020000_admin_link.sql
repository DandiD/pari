-- Pari: link da amministratore
-- La chiave da amministratore viaggia in un link (…/#gruppo&admin=chiave). Chi lo apre su un altro dispositivo
-- torna amministratore e, se il gruppo è privato, riceve anche il token per entrare senza password.
-- Se la chiave è persa del tutto, se ne genera una nuova dal SQL Editor:
--   update public.groups set admin_hash = encode(extensions.digest('<nuova chiave>', 'sha256'), 'hex') where id = '<gruppo>';

-- Risponde {"ok": true, "token": ...} se la chiave è quella dell'amministratore, altrimenti {"ok": false}
create or replace function public.pari_claim_admin(p_group text, p_admin text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare g public.groups;
begin
  select * into g from public.groups where id = p_group;
  if not found or g.admin_hash is null or p_admin is null
     or encode(extensions.digest(p_admin, 'sha256'), 'hex') <> g.admin_hash then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object('ok', true,
    'token', case when g.pass_hash is null then null else pari_private.token(g.id, g.pass_hash) end);
end;
$$;

revoke execute on function public.pari_claim_admin(text, text) from public;
grant execute on function public.pari_claim_admin(text, text) to anon, authenticated;
