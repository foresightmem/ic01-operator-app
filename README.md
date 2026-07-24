# IC01 Operator App

App Flutter per operatori, tecnici e admin IC01/GEDA.

## Aggiornamento segnalazioni ticket pubbliche

In questo branch e' stato introdotto il flusso end-to-end per permettere a un
utente esterno di aprire una segnalazione di manutenzione senza login, e per
gestire il ticket dall'app operatori/admin.

### Frontend Flutter

- Aggiunta la pagina pubblica `/segnalazione`, con alias `/support`, fuori dal
  flusso di autenticazione.
- La route pubblica accetta codici macchina normalizzati e motivi stabili:
  `out_of_stock` e `malfunction`.
- Il router normalizza gli URL con slash finale nel redirect globale, evitando
  route invalide come `/segnalazione/` con `go_router`.
- La lista manutenzioni mostra i ticket pubblici con cliente, sede, macchina,
  motivo, stato, data di apertura e azioni rapide.
- La pagina dettaglio ticket supporta il workflow `open`, `assigned`,
  `in_progress`, `resolved`, `cancelled` e mantiene compatibilita' con lo
  storico `closed`.
- I pulsanti di aggiornamento ticket non falliscono piu' in silenzio: dopo un
  update viene richiesta la riga aggiornata e, se Supabase/RLS blocca
  l'operazione, l'utente vede uno snackbar con l'errore.

### Supabase

- Aggiunta la Edge Function `public_maintenance_ticket`, esposta senza JWT, con
  CORS, validazione input, rate limiting e chiamata RPC server-side.
- Aggiunta la RPC `create_public_maintenance_ticket` per creare ticket pubblici
  senza esporre direttamente tabelle sensibili al ruolo `anon`.
- Estesa la tabella `tickets` con metadati per sorgente, motivo, reporter,
  assegnazione operatore, risoluzione e tempi di risoluzione.
- Aggiunta la tabella `ticket_events` per tracciare lifecycle/eventi ticket e
  la tabella `public_ticket_request_log` per rate limiting.
- Aggiornata la view `ticket_list` con campi utili a UI operatori/admin:
  motivo, tecnico, operatore, risoluzione e riferimenti cliente/sede/macchina.
- Aggiornate grant e policy RLS per `profiles`, `clients`, `sites`,
  `machines`, `tickets`, `ticket_events` e `notification_outbox`.
- Risolta una ricorsione RLS su `profiles` eliminando la vecchia policy
  ricorsiva e usando `current_app_role()` come funzione `SECURITY DEFINER` con
  `row_security = off`.
- Permesso agli operatori assegnati a un ticket pubblico di prenderlo in carico
  e avanzarne lo stato, mantenendo il vincolo che non possano modificare ticket
  di altri operatori.
- Corretto il trigger `record_ticket_lifecycle_event()` affinche' possa scrivere
  eventi interni su `ticket_events` senza aprire insert diretti dai client.

### Dashboard admin

- La dashboard admin include KPI sui ticket, ticket aperti/in corso/risolti,
  tempi medi di risoluzione e performance per operatore/tecnico.
- Gli errori di caricamento admin e KPI vengono mostrati in UI invece di
  lasciare la pagina in refresh/spinner continuo.
- La lista manutenzioni admin include filtri per stato, motivo, cliente,
  operatore, periodo e ordinamento.

### Verifiche eseguite

- `flutter test`
- `flutter build web`
- `supabase db lint --linked --level warning --fail-on none`
- `git diff --check`

Nota: `flutter analyze` segnala ancora alcuni warning `info` preesistenti in
file non collegati a questa modifica.
