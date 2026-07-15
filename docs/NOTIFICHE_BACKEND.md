# Notifiche Push — Backend (Supabase Edge Functions)

Questa documentazione descrive la funzione `send_notifications` e le variabili
necessarie per inviare notifiche push tramite FCM HTTP v1 (Android + iOS).

## Funzione: `send_notifications`

Path: `supabase/functions/send_notifications/index.ts`

Scopo:
- Legge la coda `notification_outbox` (status = `pending` e `scheduled_for` <= now).
- Recupera i token da `push_tokens` per l’utente.
- Invia la notifica via FCM.
- Aggiorna la riga di outbox a `sent` o `failed`.
- Rimuove token invalidi.

## Variabili ambiente richieste

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `NOTIFICATION_CRON_SECRET`
  - Segreto condiviso per autorizzare il cron (header `Authorization: Bearer <secret>`
    o `x-cron-secret: <secret>`).
- `FIREBASE_PROJECT_ID`
  - ID del progetto Firebase.
- `FIREBASE_SERVICE_ACCOUNT_JSON`
  - JSON del service account con accesso a FCM (deve includere `client_email` e
    `private_key`). Usare il JSON completo come valore della secret.

## Payload inviato a FCM

La funzione invia:
- `notification.title`
- `notification.body`
- `data` (include sempre `route: "/dashboard"` e i campi di `notification_outbox.data`)

## Esempio di chiamata (cron)

Esempio di invocazione HTTP da cron (da adattare con URL e secret):

```
POST https://<project>.supabase.co/functions/v1/send-notifications
Authorization: Bearer <NOTIFICATION_CRON_SECRET>
```

## Note

- FCM HTTP v1 usa OAuth2 con service account (non usa la legacy server key).
- FCM può inviare anche ad iOS (APNs) tramite Firebase.

## TODO

- Creare un trigger su `profiles` che inserisce `notification_settings` di default
  per i nuovi operatori `refill_operator`.
- Per Web Push servirà aggiungere il supporto FCM Web + Service Worker lato app.
- La funzione attuale è idempotente per batch (processa le righe in base allo
  stato `pending`).

## Funzione: `schedule_daily_notifications`

Path: `supabase/functions/schedule_daily_notifications/index.ts`

Scopo:
- Legge `notification_settings` (solo `enabled = true`).
- Inserisce una riga in `notification_outbox` per ogni utente, con
  `scheduled_for` impostato all’orario giornaliero.
- Evita duplicati per lo stesso utente/orario.

Autorizzazione:
- Stesso meccanismo di `send_notifications` (Bearer `NOTIFICATION_CRON_SECRET`).

Nota:
- Usa `timezone` (es. `Europe/Rome`) per calcolare l’orario locale.
