-- Pari: come ognuno preferisce essere pagato (Satispay, PayPal, bonifico)
-- I metodi stanno in groups.pay: { "<id membro>": { "sat": link, "satTel": telefono, "pp": nome PayPal.me,
--   "ppEmail": email, "iban": IBAN, "holder": intestatario, "at": data, "by": hash di chi li ha scritti } }.
-- Li vede chiunque entri nel gruppo (pari_get), non compaiono nell'elenco pubblico (pari_list).
--
-- Per evitare che qualcun altro cambi l'IBAN di un amico con il proprio, i metodi di un membro li modifica
-- solo il dispositivo che li ha scritti per primo (stessa chiave che firma le spese) o l'amministratore del gruppo.

alter table public.groups add column if not exists pay jsonb not null default '{}'::jsonb;

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
      'pay', g.pay,
      'updatedAt', (extract(epoch from g.updated_at) * 1000)::bigint),
    'expenses', coalesce(
      (select jsonb_agg(e.body || jsonb_build_object('id', e.id, 'author', e.author_hash))
         from public.expenses e where e.group_id = g.id), '[]'::jsonb));
end;
$$;

-- Salva (p_pay oggetto) o toglie (p_pay null) i metodi di pagamento di p_member
create or replace function public.pari_set_pay(p_group text, p_member text, p_pay jsonb,
  p_token text default null, p_author text default null, p_admin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.groups;
  v_old jsonb; v_by text; v_admin_ok boolean;
  v jsonb := '{}'::jsonb;
  s text;
begin
  perform pari_private.check_access(p_group, p_token);
  select * into g from public.groups where id = p_group for update;
  if not exists (select 1 from jsonb_array_elements(g.members) m where m->>'id' = p_member) then
    raise exception 'invalid_member';
  end if;
  if p_author is null or char_length(p_author) < 20 then raise exception 'invalid_author'; end if;
  v_by := pari_private.author_hash(p_group, p_author);
  v_admin_ok := g.admin_hash is not null and p_admin is not null
                and encode(extensions.digest(p_admin, 'sha256'), 'hex') = g.admin_hash;
  v_old := g.pay -> p_member;
  if v_old is not null and v_old->>'by' is not null and v_old->>'by' <> v_by and not v_admin_ok then
    raise exception 'not_author';
  end if;

  if p_pay is null then
    update public.groups set pay = pay - p_member, updated_at = now() where id = p_group;
    return;
  end if;
  if jsonb_typeof(p_pay) <> 'object' then raise exception 'invalid_pay'; end if;

  s := nullif(trim(p_pay->>'sat'), '');
  if s is not null then
    if char_length(s) > 200 or s !~ '^https://([A-Za-z0-9-]+\.)*satispay\.com/[^\s"<>]*$' then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('sat', s);
  end if;
  s := nullif(regexp_replace(coalesce(p_pay->>'satTel', ''), '[\s.-]', '', 'g'), '');
  if s is not null then
    if s !~ '^\+?[0-9]{6,15}$' then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('satTel', s);
  end if;
  s := nullif(trim(p_pay->>'pp'), '');
  if s is not null then
    if s !~ '^[A-Za-z0-9]{1,20}$' then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('pp', s);
  end if;
  s := nullif(trim(p_pay->>'ppEmail'), '');
  if s is not null then
    if char_length(s) > 120 or s !~ '^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$' then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('ppEmail', s);
  end if;
  s := nullif(upper(regexp_replace(coalesce(p_pay->>'iban', ''), '\s', '', 'g')), '');
  if s is not null then
    if s !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('iban', s);
    s := nullif(trim(p_pay->>'holder'), '');
    if s is null or char_length(s) > 70 then raise exception 'invalid_pay'; end if;
    v := v || jsonb_build_object('holder', s);
  end if;

  if v = '{}'::jsonb then
    update public.groups set pay = pay - p_member, updated_at = now() where id = p_group;
    return;
  end if;
  -- Chi li ha scritti per primo resta il proprietario, anche quando li aggiorna l'amministratore
  v := v || jsonb_build_object('at', to_char(now() at time zone 'Europe/Rome', 'YYYY-MM-DD'),
                               'by', coalesce(v_old->>'by', v_by));
  update public.groups set pay = jsonb_set(pay, array[p_member], v), updated_at = now() where id = p_group;
end;
$$;

revoke execute on function public.pari_get(text, text),
  public.pari_set_pay(text, text, jsonb, text, text, text) from public;
grant execute on function public.pari_get(text, text),
  public.pari_set_pay(text, text, jsonb, text, text, text) to anon, authenticated;
