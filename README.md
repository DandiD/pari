# Pari

Dividi le spese con gli amici. Niente account, niente limiti di spese al giorno.

- **Pagina**: un solo file, `index.html`, pubblicato su GitHub Pages.
- **Dati**: Supabase. Ogni gruppo ha un id segreto che sta nel link (`…/#id`). Chi ha il link legge e scrive quel gruppo. Chi non ce l'ha non vede niente: le tabelle non sono leggibili direttamente e tutto passa da funzioni che richiedono l'id.

```
index.html                                  l'app
config.js                                   URL e publishable key di Supabase
supabase/migrations/20261018000000_pari.sql schema, regole di accesso, funzioni
supabase/zanego.local.sql                   ricrea "Zanego ott 26" (NON va su GitHub)
```

---

## 1. Apri il progetto

Apri la cartella in VS Code. Accetta le estensioni consigliate: **Live Server** (per provare in locale) e **Supabase** (facoltativa).

## 2. Prepara il database su Supabase

Dalla dashboard del progetto `lsrqfkracjfwydzgttje`:

1. **SQL Editor → New query**. Incolla tutto `supabase/migrations/20261018000000_pari.sql` e premi **Run**.
   Il file si può rieseguire senza danni.
2. Nuova query: incolla `supabase/zanego.local.sql` e premi **Run**. Ricrea il gruppo "Zanego ott 26" con Daniele, Diego, Pietro, Mirko e Giovanni.
3. **Advisors → Security Advisor**: non dovrebbero comparire avvisi su RLS. Le tabelle hanno RLS attiva e nessuna policy, quindi è voluto.

In alternativa, con la [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started):

```bash
supabase login
supabase link --project-ref lsrqfkracjfwydzgttje
supabase db push
```

Il file `zanego.local.sql` va comunque eseguito a mano nel SQL Editor.

## 3. Inserisci la chiave

**Project Settings → API Keys**: copia la **Publishable key** (`sb_publishable_…`), oppure la legacy **anon key** (`eyJ…`). Incollala in `config.js` al posto di `INCOLLA_QUI_LA_PUBLISHABLE_KEY`.

La publishable key è fatta per stare in una pagina pubblica: si può committare.
**Non usare mai la secret key o la service_role key.**

## 4. Prova in locale

Clic destro su `index.html` → **Open with Live Server**. Poi apri il gruppo (l'id di Zanego è in `zanego.local.sql`):

```
http://127.0.0.1:5500/#<id-del-gruppo>
```

Senza chiave valida, la pagina parte in modalità anteprima con un gruppo di esempio e un avviso in alto.

## 5. Pubblica su GitHub

1. In VS Code: **Source Control → Publish to GitHub** e scegli **repository pubblico**. GitHub Pages è gratuito solo sui repository pubblici. Nel repository non ci sono segreti: `zanego.local.sql` è escluso da `.gitignore`.
2. Su github.com, nel repository: **Settings → Pages → Build and deployment → Source: Deploy from a branch**, branch `main`, cartella `/ (root)`, **Save**.
3. Dopo circa un minuto la pagina è online su `https://dandid.github.io/pari/`.

Il link da mandare agli amici:

```
https://dandid.github.io/pari/#<id-del-gruppo>
```

Dentro l'app, il pulsante **Invita** prepara il messaggio con il link giusto.

Per gli aggiornamenti successivi basta un commit e un push su `main`: Pages si ripubblica da solo.

---

## Da sapere

- **Pausa per inattività.** Sul piano gratuito Supabase mette in pausa un progetto dopo circa una settimana senza richieste. Si riattiva dalla dashboard con **Restore**, senza perdere dati.
- **Aggiornamenti in tempo reale.** Dopo ogni modifica, la pagina avvisa le altre aperte sullo stesso gruppo tramite Supabase Realtime (broadcast). Se Realtime è spento, la pagina si aggiorna comunque ogni 20 secondi e quando torni sull'app.
- **Chi ha il link può modificare tutto il gruppo**, comprese le spese degli altri. È lo stesso modello dei link di invito di Splitwise. Mandalo solo a chi ne fa parte.
- **"I tuoi gruppi"** e la scelta "Tu sei" restano salvati sul dispositivo. Su un altro telefono basta riaprire il link.
- **Se qualcosa non si carica**, controlla in **Project Settings → Data API** che l'API sia attiva e che lo schema `public` sia esposto. Le funzioni `pari_*` passano da lì.

## Funzioni del database

| Funzione | Cosa fa |
|---|---|
| `pari_get(p_group)` | gruppo e spese, `null` se l'id non esiste |
| `pari_save_group(p_group, p_name, p_members, p_example)` | crea o aggiorna il gruppo (id di almeno 20 caratteri) |
| `pari_save_expense(p_group, p_id, p_body)` | crea o aggiorna una spesa: importo in centesimi interi, massimo 3000 spese per gruppo |
| `pari_delete_expense(p_group, p_id)` | elimina una spesa |
| `pari_delete_group(p_group)` | elimina il gruppo e tutte le sue spese |
