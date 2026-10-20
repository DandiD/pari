# Pari

Dividi le spese con gli amici. Niente account, niente limiti di spese al giorno.

- **Pagina**: un solo file, `index.html`, pubblicato su GitHub Pages.
- **Dati**: Supabase. La home mostra tutti i gruppi. Ogni gruppo ha un id che sta nel link (`…/#id`); quelli senza password si aprono dalla home o dal link, quelli con password mostrano solo il nome finché non la inserisci. Le tabelle non sono leggibili direttamente: tutto passa da funzioni `pari_*`.

```
index.html                                  l'app
config.js                                   URL e publishable key di Supabase
privacy.html                                informativa privacy (linkata in fondo all'app)
fonts/, vendor/                             font e supabase-js serviti dal sito, senza CDN esterni
img/, manifest.webmanifest                   logo (pari-logo.png), icone dell'app e anteprima per la condivisione (og.png)
sw.js                                       service worker: app installabile e apribile anche offline
sitemap.xml, llms.txt                       per Google e per le AI
supabase/migrations/20261018000000_pari.sql schema, regole di accesso, funzioni
supabase/migrations/20261019000000_password.sql password facoltativa e amministratore del gruppo
supabase/migrations/20261020000000_author.sql   solo chi inserisce una spesa può modificarla
supabase/migrations/20261020010000_public_list.sql elenco pubblico dei gruppi per la home
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
- **Tutti i gruppi sono nella home, per chiunque apra Pari.** In un gruppo senza password chiunque entra e può aggiungere spese e modificare nome e partecipanti. Al primo accesso a un gruppo aperto, solo chi l'ha creato riceve l'invito a mettere una password. I gruppi di esempio non compaiono.
- **Ogni spesa la modifica solo chi l'ha inserita.** Non ci sono account, quindi "chi" è il dispositivo: ognuno ha una chiave segreta in `localStorage` e la spesa ricorda l'hash della chiave di chi l'ha creata. Il controllo è nel database, non solo nella pagina. L'amministratore del gruppo può modificare ed eliminare tutte le spese, così niente resta bloccato se qualcuno cambia telefono. Le spese inserite prima di questa regola restano modificabili da tutti. Su iPhone l'app installata e Safari hanno chiavi diverse.
- **Gruppi privati.** Chi crea un gruppo può aggiungere una password (alla creazione o da **Modifica**): nella home se ne vede solo il nome e per entrare serve la password. La password è salvata cifrata (bcrypt); dopo 10 tentativi sbagliati il gruppo si blocca per 15 minuti.
- **Amministratore.** Il dispositivo di chi crea il gruppo riceve una chiave da amministratore (in `localStorage`). Solo con quella si cambia o toglie la password e si elimina il gruppo. Se si perde (cambio telefono, dati del browser cancellati), il gruppo resta usabile ma password ed eliminazione restano bloccate. I gruppi creati prima delle password non hanno amministratore: lo diventa chi imposta la password per primo.
- **La scelta "Tu sei"**, le password già inserite e le chiavi (amministratore, autore delle spese) restano salvate sul dispositivo.
- **Se qualcosa non si carica**, controlla in **Project Settings → Data API** che l'API sia attiva e che lo schema `public` sia esposto. Le funzioni `pari_*` passano da lì.

## App sul telefono

Pari è una PWA: si installa dal browser, senza store.

- **Android (Chrome, Edge, Samsung Internet)**: in alto compare **Installa l'app**, che apre la finestra di installazione del sistema.
- **iPhone e iPad**: lo stesso pulsante spiega come fare da **Condividi → Aggiungi alla schermata Home**. Su iOS l'app installata ha dati separati da Safari, quindi "I tuoi gruppi" parte vuoto: si apre il gruppo incollando il link.
- Una volta installata, il pulsante sparisce.

`sw.js` tiene in cache la pagina, i font, gli script e le icone: l'app si apre anche senza rete, ma i gruppi si caricano solo online. La pagina è sempre scaricata prima dalla rete, quindi un push su `main` arriva subito. Se aggiungi o rinomini file statici, aggiorna la lista `SHELL` in `sw.js` e aumenta `VERSION`.

## Funzioni del database

| Funzione | Cosa fa |
|---|---|
| `pari_list()` | tutti i gruppi tranne quelli di esempio: id, nome, privato, partecipanti (vuoti per i privati) |
| `pari_get(p_group, p_token)` | gruppo e spese (ognuna con `author`, l'hash di chi l'ha inserita); `null` se l'id non esiste, `{"locked": true, "name": …}` se serve la password |
| `pari_unlock(p_group, p_pass)` | prova la password: `{token}` oppure `{error}` (`wrong_password`, `too_many_attempts`) |
| `pari_save_group(p_group, p_name, p_members, p_example, p_token, p_admin)` | crea o aggiorna il gruppo (id di almeno 20 caratteri); alla creazione registra la chiave da amministratore |
| `pari_set_password(p_group, p_token, p_admin, p_new)` | imposta, cambia o toglie (`p_new` vuota) la password; solo l'amministratore; restituisce il nuovo token |
| `pari_save_expense(p_group, p_id, p_body, p_token, p_author, p_admin)` | crea o aggiorna una spesa: importo in centesimi interi, massimo 3000 spese per gruppo; per modificarla serve la chiave di chi l'ha creata o quella da amministratore |
| `pari_delete_expense(p_group, p_id, p_token, p_author, p_admin)` | elimina una spesa, con le stesse regole della modifica |
| `pari_delete_group(p_group, p_token, p_admin)` | elimina il gruppo e tutte le sue spese; se il gruppo ha un amministratore, serve la sua chiave |

`p_token` serve solo per i gruppi con password: è derivato dalla password e smette di valere quando la password cambia.
