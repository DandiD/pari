-- Pari: quote ricevute per singola spesa
-- Chi ha pagato una spesa segna, nella scheda della spesa, chi gli ha già ridato la sua parte.
-- Le quote stanno nel corpo della spesa, in "got": { "<id membro>": { "a": centesimi, "at": "AAAA-MM-GG" } }.
-- Nei saldi una quota ricevuta conta come un pagamento da quel membro a chi ha pagato la spesa.
--
-- pari_mark_received basta avere accesso al gruppo, come per aggiungere una spesa: non ci sono account,
-- quindi chi può segnare (chi ha pagato, o l'amministratore) lo decide la pagina.
-- Cambia solo "got": importo, divisione e autore della spesa restano protetti come prima.
--
-- pari_save_expense ora tiene le quote già salvate quando si modifica una spesa, così una modifica
-- fatta da un'altra scheda aperta non le cancella. Alla creazione (e quando "Annulla" ripristina
-- una spesa eliminata) prende quelle che arrivano dalla pagina.

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
  if p_body ? 'got' and jsonb_typeof(p_body->'got') <> 'object' then raise exception 'invalid_body'; end if;
  if p_author is not null and char_length(p_author) < 20 then raise exception 'invalid_author'; end if;
  if (select count(*) from public.expenses where group_id = p_group) >= 3000
     and not exists (select 1 from public.expenses where group_id = p_group and id = p_id) then
    raise exception 'group_full';
  end if;
  perform pari_private.check_author(p_group, p_id, p_author, p_admin);
  insert into public.expenses as x (group_id, id, body, author_hash)
  values (p_group, p_id, p_body - 'id' - 'author',
          case when p_author is null then null else pari_private.author_hash(p_group, p_author) end)
  on conflict (group_id, id) do update
    set body = (excluded.body - 'got')
               || case when x.body ? 'got' then jsonb_build_object('got', x.body->'got') else '{}'::jsonb end,
        updated_at = now();
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

-- Segna (p_amount in centesimi) o toglie (p_amount null) la quota ricevuta da p_member per la spesa p_id
create or replace function public.pari_mark_received(p_group text, p_id text, p_member text,
  p_amount integer default null, p_token text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b jsonb;
begin
  perform pari_private.check_access(p_group, p_token);
  select body into b from public.expenses where group_id = p_group and id = p_id for update;
  if not found then raise exception 'expense_not_found'; end if;
  if coalesce(b->>'kind', 'expense') = 'settle' then raise exception 'invalid_body'; end if;
  if p_member is null or char_length(p_member) not between 1 and 64 or p_member = b->>'payer' then
    raise exception 'invalid_member';
  end if;
  if p_amount is null then
    b := jsonb_set(b, '{got}', coalesce(b->'got', '{}'::jsonb) - p_member);
  else
    if p_amount <= 0 or p_amount > (b->>'amount')::numeric then raise exception 'invalid_amount'; end if;
    if not (coalesce(b->'parts', '{}'::jsonb) ? p_member) then raise exception 'invalid_member'; end if;
    b := jsonb_set(b, '{got}', coalesce(b->'got', '{}'::jsonb)
           || jsonb_build_object(p_member, jsonb_build_object('a', p_amount,
                'at', to_char(now() at time zone 'Europe/Rome', 'YYYY-MM-DD'))));
  end if;
  update public.expenses set body = b, updated_at = now() where group_id = p_group and id = p_id;
  update public.groups set updated_at = now() where id = p_group;
end;
$$;

revoke execute on function public.pari_save_expense(text, text, jsonb, text, text, text),
  public.pari_mark_received(text, text, text, integer, text) from public;
grant execute on function public.pari_save_expense(text, text, jsonb, text, text, text),
  public.pari_mark_received(text, text, text, integer, text) to anon, authenticated;
