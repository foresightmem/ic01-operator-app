# Architettura DB IC-01 dev - snapshot pre KPI refill

Documento creato prima di applicare la migration `refill_productivity_kpi`.

## Scopo

Questa e una fotografia dello stato attuale del database Supabase remoto usato dall'app IC-01, prima della migration che aggiunge il KPI di produttivita refill.

Il documento contiene solo metadati tecnici, relazioni e conteggi aggregati. Non include righe applicative, dati personali o segreti.

## Snapshot

| Campo | Valore |
| --- | --- |
| Progetto Supabase | `ic01-dev` |
| Project ref | `atpfgkhechvdijqnflnc` |
| Organization id | `fvjaanxdsnflfxmdwqro` |
| Regione | `eu-west-1` |
| Stato progetto | `ACTIVE_HEALTHY` |
| Host DB | `db.atpfgkhechvdijqnflnc.supabase.co` |
| PostgreSQL | `17.6.1.044` |
| Timezone server | `UTC` |
| Snapshot verificato | `2026-08-25T12:36:48Z` |

## Stato KPI refill

La dashboard admin fallisce con `PGRST202` perche la funzione RPC non esiste ancora nel DB remoto:

`public.get_refill_productivity_kpi(p_period_days, p_theoretical_work_hours_per_day, p_timezone)`

Stato attuale verificato:

| Oggetto | Stato |
| --- | --- |
| RPC `get_refill_productivity_kpi` | Assente |
| Tabella `refills` | Presente, formato legacy |
| Colonne snapshot refill dosi | Assenti |
| Righe `refills` storiche | `29` |
| RPC `perform_refill_consumable` | Presente, ma non scrive eventi in `refills` |

Colonne che la migration KPI deve aggiungere a `public.refills`:

- `consumable_type`
- `previous_units`
- `capacity_units`
- `refilled_units`
- `snapshot_metadata`

## Conteggi tabelle

Conteggi esatti letti dal remoto al momento dello snapshot.

| Tabella | Righe |
| --- | ---: |
| `beverage_recipe_items` | 7 |
| `beverage_recipes` | 3 |
| `clients` | 10 |
| `device_commands` | 11 |
| `device_status` | 1 |
| `devices` | 1 |
| `dispense_events` | 0 |
| `firmware_versions` | 2 |
| `machine_consumables` | 117 |
| `machines` | 24 |
| `notification_outbox` | 2 |
| `notification_settings` | 4 |
| `operator_unavailability` | 4 |
| `organizations` | 1 |
| `profiles` | 7 |
| `push_tokens` | 3 |
| `refills` | 29 |
| `sites` | 10 |
| `temp_machine_assignments` | 21 |
| `ticket_events` | 4 |
| `tickets` | 4 |
| `visits` | 2 |

## Estensioni e tipi

### Enum `public.beverage_type`

Valori:

- `coffee`
- `cappuccino`
- `powder_drink`

### Enum `public.consumable_type`

Valori:

- `coffee`
- `milk`
- `powder`
- `water`
- `hot`
- `cold`

## Tabelle core

### `public.organizations`

Tenant logico dell'app.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `name` | `text` | Obbligatoria |
| `created_at` | `timestamptz` | Obbligatoria, default `now()` |

Uso: tutte le entita principali sono scoperte per `organization_id`.

### `public.profiles`

Profilo applicativo collegato a `auth.users`.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, FK verso `auth.users` |
| `full_name` | `text` | Nome visualizzato |
| `role` | `text` | Obbligatoria, check: `refill_operator`, `technician`, `admin` |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |
| `organization_id` | `uuid` | Obbligatoria, FK verso `organizations` |

Uso:

- determina ruolo applicativo via `current_app_role()`;
- determina tenant via `current_app_organization_id()`;
- collega operatori, tecnici, admin e creatori record.

### `public.clients`

Clienti finali.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `name` | `text` | Obbligatoria |
| `vat_number` | `text` | Partita IVA / identificativo fiscale |
| `notes` | `text` | Note operative |
| `created_at` | `timestamptz` | Default `now()` |
| `created_by` | `uuid` | FK verso `profiles` |
| `updated_at` | `timestamptz` | Obbligatoria, default `now()` |
| `organization_id` | `uuid` | Obbligatoria, FK verso `organizations` |

Relazioni:

- `clients` 1:N `sites`
- `clients` 1:N `tickets`
- `clients` 1:N `visits`

### `public.sites`

Sedi fisiche dei clienti.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `client_id` | `uuid` | Obbligatoria, FK verso `clients`, cascade delete |
| `name` | `text` | Obbligatoria |
| `address` | `text` | Indirizzo |
| `city` | `text` | Citta |
| `lat` | `numeric` | Campo geografico legacy |
| `lon` | `numeric` | Campo geografico legacy |
| `latitude` | `numeric` | Check range latitudine |
| `longitude` | `numeric` | Check range longitudine |
| `created_at` | `timestamptz` | Default `now()` |
| `created_by` | `uuid` | FK verso `profiles` |
| `updated_at` | `timestamptz` | Obbligatoria, default `now()` |
| `organization_id` | `uuid` | Obbligatoria, FK verso `organizations` |

Relazioni:

- `sites` N:1 `clients`
- `sites` 1:N `machines`
- `sites` 1:N `tickets`
- `sites` 1:N `visits`

### `public.machines`

Distributori automatici.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `code` | `text` | Obbligatoria, codice macchina |
| `site_id` | `uuid` | Obbligatoria, FK verso `sites`, cascade delete |
| `assigned_operator_id` | `uuid` | Obbligatoria, FK verso `profiles` |
| `capacity_water_ml` | `integer` | Capacita acqua legacy |
| `current_fill_percent` | `numeric` | Obbligatoria, default `100` |
| `yearly_shots` | `integer` | Obbligatoria, default `0` |
| `hw_serial` | `text` | Serial hardware |
| `water_tank_enabled` | `boolean` | Obbligatoria, default `false` |
| `temperature_mode` | `text` | Obbligatoria, default `hot`, check `hot`/`cold` |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |
| `created_by` | `uuid` | FK verso `profiles` |
| `organization_id` | `uuid` | Obbligatoria, FK verso `organizations` |

Relazioni:

- `machines` N:1 `sites`
- `machines` N:1 `profiles` tramite `assigned_operator_id`
- `machines` 1:N `machine_consumables`
- `machines` 1:N `refills`
- `machines` 1:N `tickets`
- `machines` 1:N `dispense_events`
- `machines` 1:N `devices`

Note:

- `current_fill_percent` viene sincronizzato da trigger sui consumabili.
- `code` ha indice unico normalizzato.
- l'assegnazione effettiva puo essere sovrascritta da `temp_machine_assignments`.

### `public.machine_consumables`

Stato consumabili per macchina.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `machine_id` | `uuid` | Obbligatoria, FK verso `machines`, cascade delete |
| `type` | `consumable_type` | Obbligatoria |
| `capacity_units` | `integer` | Obbligatoria, default `0`, non negativa |
| `current_units` | `integer` | Obbligatoria, default `0`, non negativa |
| `is_enabled` | `boolean` | Obbligatoria, default `true` |
| `updated_at` | `timestamptz` | Obbligatoria, default `now()` |

Vincoli:

- unique `machine_id, type`
- `current_units <= capacity_units`
- quantita non negative

Uso:

- e la fonte attuale della percentuale di riempimento per consumabile;
- la vista `machine_effective_consumables` alimenta la pagina dettaglio macchina Flutter;
- la RPC `perform_refill_consumable` resetta `current_units` a `capacity_units`.

### `public.refills`

Storico refill.

RLS: abilitata.

Stato attuale: legacy, non ancora adatto al KPI dosi/refill.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `machine_id` | `uuid` | Obbligatoria, FK verso `machines`, cascade delete |
| `operator_id` | `uuid` | Obbligatoria, FK verso `profiles` |
| `created_at` | `timestamptz` | Default `now()` |
| `previous_fill_percent` | `numeric` | Percentuale prima del refill legacy |
| `new_fill_percent` | `numeric` | Obbligatoria, default `100` |
| `undone_at` | `timestamptz` | Annullamento |
| `undone_by` | `uuid` | FK verso `profiles` |
| `note` | `text` | Nota |

Limite attuale:

- non salva il tipo consumabile ricaricato;
- non salva unita precedenti, capacita o unita effettivamente ricaricate;
- la RPC moderna `perform_refill_consumable` non inserisce righe in questa tabella;
- i 29 record storici sono utili come storico evento, ma non bastano per calcolare produttivita in dosi.

Trigger:

- `on_refill_insert` esegue `apply_refill()` dopo insert.

## Ticketing e manutenzione

### `public.tickets`

Chiamate di manutenzione.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `machine_id` | `uuid` | FK verso `machines` |
| `client_id` | `uuid` | FK verso `clients` |
| `site_id` | `uuid` | FK verso `sites` |
| `status` | `text` | Default `open`; check workflow |
| `reason` | `text` | Motivo ticket, check dedicato |
| `source` | `text` | Default `operator_app`, check dedicato |
| `requester_name` | `text` | Richiedente |
| `requester_contact` | `text` | Contatto |
| `description` | `text` | Descrizione |
| `assigned_operator_id` | `uuid` | FK verso `profiles` |
| `assigned_technician_id` | `uuid` | FK verso `profiles` |
| `assigned_at` | `timestamptz` | Assegnazione |
| `resolved_at` | `timestamptz` | Risoluzione |
| `closed_at` | `timestamptz` | Chiusura |
| `resolution_time_seconds` | `integer` | Durata risoluzione |
| `duplicate_report_count` | `integer` | Conteggio segnalazioni duplicate |
| `machine_code_snapshot` | `text` | Codice macchina fotografato |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |

Workflow status:

- `open`
- `assigned`
- `in_progress`
- `resolved`
- `cancelled`
- `closed`

Trigger:

- `tickets_touch_lifecycle`
- `set_timestamp_on_tickets`
- `tickets_record_lifecycle_event`

### `public.ticket_events`

Eventi lifecycle ticket.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `ticket_id` | `uuid` | FK verso `tickets`, cascade delete |
| `event_type` | `text` | Check event type |
| `created_at` | `timestamptz` | Default `now()` |
| `metadata` | `jsonb` | Default `{}` |

### `public.visits`

Visite operative.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `operator_id` | `uuid` | FK verso `profiles` |
| `client_id` | `uuid` | FK verso `clients` |
| `site_id` | `uuid` | FK verso `sites` |
| `visit_type` | `text` | Check: `refill`, `maintenance` |
| `ticket_id` | `uuid` | FK verso `tickets` |
| `notes` | `text` | Note |
| `created_at` | `timestamptz` | Default `now()` |

Nota sicurezza: essendo nel namespace `public`, l'assenza di RLS su `visits` va tenuta sotto controllo insieme ai grant effettivi.

## Assegnazioni temporanee e indisponibilita

### `public.temp_machine_assignments`

Assegnazioni temporanee di macchine.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `machine_id` | `uuid` | FK verso `machines`, cascade delete |
| `original_operator_id` | `uuid` | FK verso `profiles` |
| `new_operator_id` | `uuid` | FK verso `profiles` |
| `start_date` | `date` | Inizio |
| `end_date` | `date` | Fine |
| `status` | `text` | Default `suggested`; check `suggested`, `confirmed`, `rejected` |
| `created_at` | `timestamptz` | Default `now()` |

Uso:

- determina assegnazione effettiva tramite le viste `machine_effective_assignment` e `machine_effective_consumables`;
- influenza l'autorizzazione di `perform_refill_consumable`.

### `public.operator_unavailability`

Indisponibilita operatori.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `operator_id` | `uuid` | FK verso `profiles`, cascade delete |
| `start_date` | `date` | Inizio |
| `end_date` | `date` | Fine |
| `reason` | `text` | Motivo |
| `created_at` | `timestamptz` | Default `now()` |

## Notifiche

### `public.notification_settings`

Preferenze notifiche per utente.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `user_id` | `uuid` | PK, FK verso `profiles`, cascade delete |
| `enabled` | `boolean` | Abilitazione |
| `hour` | `integer` | Check ora |
| `minute` | `integer` | Check minuto |
| `timezone` | `text` | Default `Europe/Rome` |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |

### `public.notification_outbox`

Coda notifiche.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `user_id` | `uuid` | FK verso `profiles` |
| `title` | `text` | Titolo |
| `body` | `text` | Corpo |
| `data` | `jsonb` | Default `{}` |
| `status` | `text` | Check `pending`, `sent`, `failed` |
| `attempts` | `integer` | Default `0` |
| `last_error` | `text` | Ultimo errore |
| `scheduled_for` | `timestamptz` | Obbligatoria |
| `sent_at` | `timestamptz` | Invio |
| `created_at` | `timestamptz` | Default `now()` |

Trigger:

- `notification_outbox_immediate_trigger`

### `public.push_tokens`

Token push per device.

RLS: abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `user_id` | `uuid` | FK verso `profiles`, cascade delete |
| `device_id` | `text` | Device app |
| `platform` | `text` | Check `android`, `ios`, `web` |
| `token` | `text` | Token provider |
| `created_at` | `timestamptz` | Default `now()` |
| `updated_at` | `timestamptz` | Default `now()` |

Vincolo:

- unique `device_id, platform`

## Firmware, device e telemetria

Questa area contiene tabelle non tutte protette da RLS. L'accesso reale dipende quindi dai grant e dalle credenziali usate dai flussi device/backend.

### `public.devices`

Device fisici associabili alle macchine.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `device_id` | `text` | Unique |
| `device_secret` | `text` | Segreto corrente |
| `device_secret_next` | `text` | Segreto prossimo |
| `machine_id` | `uuid` | FK verso `machines` |
| `created_at` | `timestamptz` | Default `now()` |

### `public.device_status`

Ultimo stato noto device.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `device_id` | `text` | PK, FK verso `devices`, cascade delete |
| `last_seen_at` | `timestamptz` | Ultimo ping |
| `fw_version` | `text` | Firmware rilevato |

### `public.device_commands`

Comandi verso device.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `device_id` | `text` | FK verso `devices`, cascade delete |
| `command` | `text` | Comando |
| `payload` | `jsonb` | Parametri |
| `status` | `text` | Default `pending` |
| `created_at` | `timestamptz` | Default `now()` |
| `sent_at` | `timestamptz` | Invio |
| `ack_at` | `timestamptz` | Ack |

### `public.dispense_events`

Eventi erogazione registrati dal device.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `machine_id` | `uuid` | FK verso `machines`, cascade delete |
| `beverage` | `beverage_type` | Bevanda erogata |
| `device_id` | `text` | Device sorgente |
| `device_counter` | `bigint` | Contatore device |
| `created_at` | `timestamptz` | Default `now()` |

Vincolo:

- unique `machine_id, device_counter`

### `public.firmware_versions`

Versioni firmware disponibili.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `version` | `text` | PK |
| `storage_path` | `text` | Path storage |
| `sha256` | `text` | Hash |
| `mandatory` | `boolean` | Default `false` |
| `released_at` | `timestamptz` | Default `now()` |

### `public.beverage_recipes`

Ricette bevande.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `beverage` | `beverage_type` | PK |
| `is_active` | `boolean` | Default `true` |
| `updated_at` | `timestamptz` | Default `now()` |

### `public.beverage_recipe_items`

Ingredienti per ricetta.

RLS: non abilitata.

| Colonna | Tipo | Note |
| --- | --- | --- |
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `beverage` | `beverage_type` | FK verso `beverage_recipes`, cascade delete |
| `consumable` | `consumable_type` | Consumabile da decrementare |
| `delta_units` | `integer` | Quantita da sottrarre |
| `require_water_tank` | `boolean` | Default `false` |

Vincolo:

- unique `beverage, consumable`

## Viste

### `public.machine_states`

Calcola stato macchina combinando assegnazione effettiva e peggior percentuale dei consumabili abilitati.

Campi principali:

- `machine_id`
- `code`
- `site_id`
- `assigned_operator_id`
- `current_fill_percent`
- `state`
- `yearly_shots`
- `created_at`
- `updated_at`

### `public.machine_effective_assignment`

Espone l'operatore effettivo della macchina, considerando assegnazioni temporanee confermate.

Campi principali:

- dati macchina;
- dati sito;
- dati cliente;
- `effective_operator_id`;
- `effective_operator_name`;
- stato/percentuale.

### `public.machine_effective_consumables`

Vista centrale per refill consumabili nella UI operatore.

Campi principali:

- `machine_id`
- `machine_code`
- `effective_operator_id`
- cliente/sito;
- `type`
- `capacity_units`
- `current_units`
- `fill_percent`

Uso:

- alimenta il dettaglio macchina Flutter;
- consente alla UI di vedere piu consumabili per macchina.

### `public.client_states_effective`

Aggrega lo stato clienti per operatore effettivo.

Campi principali:

- `effective_operator_id`
- `client_id`
- `total_machines`
- `machines_to_refill`
- `worst_state_rank`

### `public.client_states`

Aggregato cliente/stato.

### `public.client_machines`

Lista macchine per cliente/operatore usata da schermate operative.

### `public.machine_states_v2`

Variante dello stato macchina.

### `public.client_states_v2`

Variante dello stato cliente.

### `public.operator_ranking`

Ranking operatori basato su `yearly_shots`.

### `public.ticket_list`

Vista UI ticket con join verso macchina, cliente, sede, operatore e tecnico.

Campi principali:

- ticket lifecycle;
- identificativi e nomi macchina/cliente/sede;
- tecnico assegnato;
- operatore assegnato;
- tempi di risoluzione.

## Funzioni e RPC principali

### Autorizzazione e contesto

#### `public.current_app_role()`

Funzione `SECURITY DEFINER`, stabile, con `row_security = off`.

Uso:

- legge il ruolo applicativo da `profiles`;
- evita ricorsioni RLS nelle policy;
- usata da molte policy per distinguere `admin`, `technician`, `refill_operator`.

#### `public.current_app_organization_id()`

Funzione `SECURITY DEFINER`, stabile, con `row_security = off`.

Uso:

- legge il tenant dell'utente corrente da `profiles`;
- centralizza lo scoping multi-organizzazione.

#### Funzioni helper accesso

Sono presenti funzioni `SECURITY DEFINER` stabili per verificare accesso a oggetti specifici:

- `machine_has_operator_access`
- `client_has_operator_access`
- `site_has_operator_access`
- altre funzioni helper correlate ad onboarding e ticket

### Refill

#### `public.perform_refill_consumable(p_machine_id uuid, p_type public.consumable_type)`

RPC attualmente usata dal flusso moderno di refill consumabile.

Stato attuale:

- `SECURITY DEFINER`;
- `search_path public`;
- richiede `auth.uid()`;
- controlla che l'utente sia operatore effettivo della macchina;
- controlla appartenenza alla stessa organizzazione;
- legge `machine_consumables.current_units` e `capacity_units`;
- aggiorna `current_units = capacity_units`;
- ritorna JSON con dati aggiornati.

Limite per KPI:

- non inserisce una riga in `public.refills`;
- non registra `previous_units`, `capacity_units`, `refilled_units`;
- quindi il KPI produttivita refill non ha ancora fonte dati numerica affidabile.

#### `public.perform_refill(p_machine_id uuid)`

RPC legacy.

Stato attuale:

- inserisce una riga in `public.refills`;
- aggiorna `machines.current_fill_percent = 100`;
- lavora su percentuale macchina, non su singolo consumabile.

#### `public.apply_refill()`

Trigger function collegata a `refills`.

Effetto:

- aggiorna `machines.current_fill_percent` usando `new_fill_percent` dopo un insert in `refills`.

#### `public.sync_machine_current_fill_percent()`

Trigger function collegata a `machine_consumables`.

Effetto:

- sincronizza `machines.current_fill_percent` dai consumabili attivi, in particolare hot/cold quando presenti.

### Dispense

#### `public.register_dispense(...)`

RPC device/backend.

Stato attuale:

- `SECURITY DEFINER`;
- inserisce in `dispense_events`;
- deduplica su `machine_id, device_counter`;
- applica la ricetta bevanda;
- decrementa `machine_consumables` in base a `beverage_recipe_items`.

### Ticketing e onboarding

RPC/funzioni presenti:

- `create_public_maintenance_ticket`
- `record_ticket_lifecycle_event`
- `touch_ticket_lifecycle`
- `add_site_to_client`
- `create_client_with_primary_site`
- `create_machine_for_site`
- `delete_onboarding_client`
- `onboarding_actor_context`
- `site_has_no_machines`

### Utility

Funzioni presenti:

- `fill_percent_to_state`
- `state_severity`
- `normalize_machine_code`
- `set_current_timestamp_updated_at`
- `touch_updated_at`
- `notify_outbox_immediate`
- `whoami`

## Trigger

| Tabella | Trigger | Evento | Funzione |
| --- | --- | --- | --- |
| `clients` | `set_timestamp_on_clients` | BEFORE UPDATE | `set_current_timestamp_updated_at` |
| `machine_consumables` | `trg_sync_machine_current_fill_percent` | AFTER INSERT/UPDATE | `sync_machine_current_fill_percent` |
| `machines` | `set_timestamp_on_machines` | BEFORE UPDATE | `set_current_timestamp_updated_at` |
| `notification_outbox` | `notification_outbox_immediate_trigger` | AFTER INSERT | `notify_outbox_immediate` |
| `notification_settings` | `notification_settings_touch_updated_at` | BEFORE UPDATE | `touch_updated_at` |
| `push_tokens` | `push_tokens_touch_updated_at` | BEFORE UPDATE | `touch_updated_at` |
| `refills` | `on_refill_insert` | AFTER INSERT | `apply_refill` |
| `sites` | `set_timestamp_on_sites` | BEFORE UPDATE | `set_current_timestamp_updated_at` |
| `tickets` | `tickets_touch_lifecycle` | BEFORE INSERT/UPDATE | `touch_ticket_lifecycle` |
| `tickets` | `set_timestamp_on_tickets` | BEFORE UPDATE | `set_current_timestamp_updated_at` |
| `tickets` | `tickets_record_lifecycle_event` | AFTER INSERT/UPDATE | `record_ticket_lifecycle_event` |

## Indici principali

### Organizzazione e anagrafiche

- `clients_organization_id_idx`
- `sites_client_id_idx`
- `sites_organization_id_idx`
- `machines_organization_id_idx`
- `machines_created_by_idx`
- `machines_code_normalized_unique_idx`

### Consumabili e macchine

- unique `machine_consumables_machine_id_type_key`

### Ticketing

- indici su `tickets.machine_id`
- indici su `tickets.client_id`
- indici su `tickets.status`
- indici su `tickets.created_at`
- indici su `tickets.resolved_at`
- indici su `tickets.assigned_operator_id`
- indici su `tickets.assigned_technician_id`
- indici su `tickets.reason`
- indice unico per ticket aperti per macchina/motivo
- `ticket_events_ticket_id_created_at_idx`

### Visite e assegnazioni

- `visits_operator_created_at_idx`
- `visits_client_created_at_idx`
- indici su `temp_machine_assignments`

### Gap indici per KPI refill

Prima della migration KPI non risultano indici dedicati su:

- `refills.created_at, operator_id`
- `refills.machine_id, created_at`

La migration KPI prevede indici mirati per interrogazioni su periodo, operatore e macchina.

## RLS e access model

### Pattern generale

Le tabelle applicative principali usano RLS e policy basate su:

- utente corrente `auth.uid()`;
- ruolo applicativo letto da `profiles.role`;
- organizzazione corrente letta da `profiles.organization_id`;
- accesso diretto come owner/creator;
- accesso tramite assegnazione operatore;
- accesso admin/technician su stessa organizzazione.

### Tabelle con RLS abilitata

- `organizations`
- `profiles`
- `clients`
- `sites`
- `machines`
- `machine_consumables`
- `refills`
- `tickets`
- `ticket_events`
- `temp_machine_assignments`
- `operator_unavailability`
- `notification_settings`
- `notification_outbox`
- `push_tokens`

### Tabelle senza RLS

- `visits`
- `devices`
- `device_status`
- `device_commands`
- `dispense_events`
- `firmware_versions`
- `beverage_recipes`
- `beverage_recipe_items`

Nota: queste tabelle sono in schema `public`; vanno considerate insieme ai grant effettivi e all'esposizione REST Supabase. Non sono parte diretta della migration KPI refill, ma sono un punto da auditare separatamente.

### Policy principali osservate

`clients`, `sites`, `machines`:

- select scoped per organizzazione;
- admin e technician vedono i record dell'organizzazione;
- operatori vedono record assegnati o accessibili via helper.

`machine_consumables`:

- select tramite accesso alla macchina;
- insert/update riservati ad admin stessa organizzazione;
- refill operativo passa dalla RPC.

`profiles`:

- un utente vede se stesso;
- admin vede profili della stessa organizzazione.

`refills`:

- select admin o record propri;
- insert permesso a operatore coerente con accesso macchina;
- presenti anche policy legacy/public oltre a policy authenticated.

`tickets`:

- select basata su ruolo, assegnazione e organizzazione;
- insert per admin/technician o flussi pubblici dedicati;
- update per ruoli/assegnatari compatibili.

`temp_machine_assignments`:

- admin gestisce;
- operatori coinvolti vedono assegnazioni confermate.

`notification_settings`, `notification_outbox`, `push_tokens`:

- accesso owner-based.

## Flussi dati rilevanti

### Refill consumabile attuale

1. Operatore apre il dettaglio macchina.
2. La UI legge i consumabili da `machine_effective_consumables`.
3. L'operatore esegue refill di un consumabile.
4. La app chiama `perform_refill_consumable(p_machine_id, p_type)`.
5. La RPC verifica auth, assegnazione effettiva e organizzazione.
6. La RPC aggiorna `machine_consumables.current_units = capacity_units`.
7. Il trigger `sync_machine_current_fill_percent` aggiorna `machines.current_fill_percent`.
8. Nessuna riga numerica viene scritta in `refills`.

Conseguenza: il refill funziona operativamente, ma non produce ancora dati sufficienti per il KPI produttivita.

### Refill legacy

1. Una chiamata legacy usa `perform_refill(p_machine_id)`.
2. La RPC inserisce in `refills`.
3. Il trigger `apply_refill()` aggiorna `machines.current_fill_percent`.

Conseguenza: lo storico esiste, ma e basato su percentuale macchina, non su dosi/refill per consumabile.

### Erogazione device

1. Device/backend chiama `register_dispense`.
2. La funzione inserisce `dispense_events`.
3. In base a `beverage_recipe_items`, decrementa `machine_consumables`.
4. Il trigger sincronizza la percentuale macchina.

### Ticket lifecycle

1. Ticket creato da app/operatore/admin/flusso pubblico.
2. Trigger normalizzano timestamps e lifecycle.
3. Eventi vengono scritti in `ticket_events`.
4. Vista `ticket_list` aggrega dati per dashboard e app.

## Impatto atteso della migration KPI refill

La migration prevista e additiva sulla tabella `refills` e sostitutiva sulla RPC `perform_refill_consumable`.

Modifiche attese:

- aggiunta colonne snapshot su `refills`;
- aggiunta check su `refilled_units`;
- aggiunta indici dedicati KPI;
- sostituzione di `perform_refill_consumable` per registrare un evento refill quando `refilled_units > 0`;
- creazione RPC admin-only `get_refill_productivity_kpi`;
- grant `EXECUTE` solo a `authenticated`;
- `notify pgrst, 'reload schema'`.

## Rischi tecnici da verificare prima del deploy

### Regressione refill operativo

La RPC `perform_refill_consumable` e nel percorso critico dell'operatore. Anche se la logica viene mantenuta, sostituire la funzione puo introdurre regressioni se:

- il nome parametri non coincide con quello chiamato dalla app;
- qualche macchina non ha righe consumabili coerenti;
- un operatore lavora tramite assegnazione temporanea non coperta;
- i vincoli nuovi su `refills` intercettano dati inattesi.

Mitigazione prevista:

- migration gia testata in ambiente Postgres temporaneo;
- test SQL dedicato;
- transazione e lock `for update` sulla riga consumabile;
- insert evento solo se `refilled_units > 0`.

### Schema cache PostgREST

L'errore attuale `PGRST202` indica funzione non visibile nello schema cache. Dopo deploy serve reload:

```sql
notify pgrst, 'reload schema';
```

### Dati legacy

I 29 record storici in `refills` non hanno snapshot dosi. Dopo migration:

- i record legacy resteranno consultabili;
- il KPI numerico diventera affidabile solo sui refill nuovi;
- finche ci sono pochi eventi nuovi, la dashboard puo mostrare dati insufficienti.

### RLS/admin

La RPC KPI deve essere admin-only. Il controllo deve avvenire dentro la funzione, non solo via grant.

### Sicurezza `SECURITY DEFINER`

Le nuove RPC devono:

- impostare `search_path = public`;
- verificare `auth.uid()`;
- verificare ruolo `admin` per la KPI;
- revocare `EXECUTE` da `public` e `anon` dove necessario.

## Checklist pre-migration

- [x] Snapshot architettura DB remoto documentato.
- [x] Conteggi tabelle principali documentati.
- [x] Gap KPI refill documentato.
- [x] Nessuna migration applicata durante la creazione di questo documento.
- [ ] Approvazione esplicita deploy migration.
- [ ] Applicazione migration su Supabase remoto.
- [ ] Verifica presenza RPC in `pg_proc`.
- [ ] Verifica chiamata admin a `get_refill_productivity_kpi`.
- [ ] Verifica refill reale o simulato post-deploy.
- [ ] Verifica dashboard admin dopo reload schema.

