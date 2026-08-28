# Migration refill_productivity_kpi

Documento operativo della migration applicata per abilitare il KPI produttivita refill nella Dashboard Admin.

## Riferimenti

| Campo | Valore |
| --- | --- |
| Progetto Supabase | `ic01-dev` |
| Project ref | `atpfgkhechvdijqnflnc` |
| Migration locale | `supabase/migrations/20260825091804_refill_productivity_kpi.sql` |
| Nome migration remota | `refill_productivity_kpi` |
| Versione registrata remota | `20260825124730` |
| Data applicazione | `2026-08-25` |
| Documento pre-migration | `docs/db-architecture-ic01-dev-pre-refill-productivity-kpi.md` |
| Documento funzionale KPI | `docs/refill-productivity-kpi.md` |

## Obiettivo

Prima della migration la dashboard admin chiamava la RPC:

`public.get_refill_productivity_kpi(p_period_days, p_theoretical_work_hours_per_day, p_timezone)`

Il DB remoto non aveva questa funzione, quindi PostgREST restituiva:

`PGRST202 - Could not find the function public.get_refill_productivity_kpi(...) in the schema cache`

Inoltre il flusso moderno di refill consumabile aggiornava `machine_consumables`, ma non registrava in `refills` uno snapshot numerico del refill. Questo impediva di calcolare dosi refillate, produttivita teorica e produttivita osservata.

La migration risolve entrambi i punti:

- crea la RPC admin-only `get_refill_productivity_kpi`;
- aggiorna `perform_refill_consumable` per salvare un evento refill quando c'e una ricarica positiva;
- estende `refills` con colonne snapshot;
- aggiunge indici per query KPI.

## Oggetti modificati

### Tabella `public.refills`

Sono state aggiunte colonne additive e retrocompatibili.

| Colonna | Tipo | Default | Scopo |
| --- | --- | --- | --- |
| `consumable_type` | `public.consumable_type` | `NULL` | Consumabile ricaricato |
| `previous_units` | `integer` | `NULL` | Unita presenti prima del refill |
| `capacity_units` | `integer` | `NULL` | Capacita configurata al momento del refill |
| `refilled_units` | `integer` | `NULL` | Unita effettivamente ricaricate |
| `snapshot_metadata` | `jsonb` | `{}` | Metadati del punto di cattura |

I record storici restano validi e non vengono riscritti. Per questi record le nuove colonne restano `NULL`, quindi il KPI li considera legacy.

### Constraint

E stato aggiunto il constraint:

`refills_units_snapshot_nonnegative`

Garantisce che, quando valorizzati, i campi numerici dello snapshot non siano negativi:

- `previous_units >= 0`
- `capacity_units >= 0`
- `refilled_units >= 0`

### Indici

Sono stati aggiunti due indici parziali sui refill non annullati.

| Indice | Definizione logica | Uso |
| --- | --- | --- |
| `refills_productivity_created_operator_idx` | `(created_at, operator_id) where undone_at is null` | KPI per periodo/operatore |
| `refills_productivity_machine_created_idx` | `(machine_id, created_at desc) where undone_at is null` | Audit/refill recenti per macchina |

## RPC `perform_refill_consumable`

La funzione esisteva gia ed era usata dall'app operatore per fare refill di un singolo consumabile.

Firma invariata:

```sql
public.perform_refill_consumable(
  p_machine_id uuid,
  p_type public.consumable_type
)
returns json
```

### Comportamento dopo migration

1. Legge `auth.uid()`.
2. Verifica che l'utente sia autenticato.
3. Verifica che la macchina appartenga alla stessa organizzazione dell'utente.
4. Verifica che l'utente sia assegnatario diretto o assegnatario temporaneo confermato.
5. Blocca la riga di `machine_consumables` con `for update`.
6. Legge `current_units` e `capacity_units`.
7. Calcola `refilled_units = greatest(capacity_units - current_units, 0)`.
8. Aggiorna il consumabile a pieno: `current_units = capacity_units`.
9. Se `refilled_units > 0`, inserisce un evento in `public.refills`.
10. Ritorna un JSON con risultato e id refill eventuale.

### JSON di ritorno

Campi principali:

- `ok`
- `machine_id`
- `type`
- `previous_units`
- `capacity_units`
- `new_units`
- `refilled_units`
- `refill_id`
- `event_recorded`

`event_recorded` vale `false` se il refill viene premuto quando il consumabile e gia pieno o non produce delta positivo. In quel caso lo stato macchina viene comunque normalizzato, ma il KPI non riceve un evento artificiale.

### Snapshot inserito in `refills`

Quando il delta e positivo, viene inserita una riga con:

- `machine_id`
- `operator_id`
- `previous_fill_percent`
- `new_fill_percent = 100`
- `consumable_type`
- `previous_units`
- `capacity_units`
- `refilled_units`
- `snapshot_metadata`

`snapshot_metadata` include:

```json
{
  "source": "perform_refill_consumable",
  "snapshot": "before_refill",
  "observed_refill_window_timezone": "Europe/Rome"
}
```

## RPC `get_refill_productivity_kpi`

Nuova funzione chiamata dalla Dashboard Admin.

Firma:

```sql
public.get_refill_productivity_kpi(
  p_period_days integer default 30,
  p_timezone text default 'Europe/Rome',
  p_theoretical_work_hours_per_day numeric default 6
)
returns jsonb
```

### Sicurezza

La funzione e:

- `SECURITY DEFINER`;
- `STABLE`;
- `set search_path = ''`;
- `set row_security = off`;
- eseguibile da `authenticated`;
- non eseguibile da `anon` o `public`;
- protetta internamente da controllo `auth.uid()`;
- protetta internamente da controllo `profiles.role = 'admin'`.

Un utente non admin riceve errore:

`Admin role required`

### Scoping dati

Il KPI legge solo dati della stessa organizzazione dell'admin corrente:

- recupera `role` e `organization_id` da `public.profiles`;
- filtra i refill tramite join con `public.machines`;
- considera solo macchine della stessa `organization_id`.

### Periodi

La funzione calcola:

- periodo corrente: ultimi `p_period_days`;
- periodo precedente: finestra immediatamente precedente di pari durata.

`p_period_days` viene normalizzato tra `1` e `366`.

La timezone default e `Europe/Rome`.

### Metriche principali

Nel payload `summary`:

- `total_refilled_doses`
- `refill_count`
- `unique_machine_count`
- `active_refill_days`
- `theoretical_hours`
- `observable_days`
- `observed_refill_hours`
- `doses_for_observed_rate`
- `doses_per_theoretical_hour`
- `doses_per_observed_hour`
- `observed_window_utilization`
- `theoretical_residual_capacity_hours`
- `refill_with_quantity_count`
- `legacy_without_quantity_count`
- `invalid_quantity_count`

Nel payload `operators` la stessa logica e calcolata per singolo operatore.

### Dati legacy

I refill storici senza `refilled_units`:

- contano nel numero refill;
- sono marcati come `legacy_without_quantity_count`;
- non contribuiscono alle metriche basate sulle dosi.

Questo evita di inventare dosi retroattive da percentuali legacy.

## Grant

Grant finali verificati per entrambe le RPC:

```text
postgres=X/postgres
authenticated=X/postgres
service_role=X/postgres
```

`anon` e `public` non hanno `EXECUTE`.

Funzioni verificate:

- `public.get_refill_productivity_kpi(integer, text, numeric)`
- `public.perform_refill_consumable(uuid, public.consumable_type)`

## Reload schema

La migration termina con:

```sql
notify pgrst, 'reload schema';
```

Dopo il deploy e stato inviato anche un secondo reload manuale.

Questo serve a risolvere il caso in cui PostgREST abbia ancora in cache lo schema precedente e continui a restituire `PGRST202`.

## Verifiche post-deploy eseguite

### Oggetti DB

Verificati con query read-only:

- `public.refills.refilled_units` presente;
- `public.refills.snapshot_metadata` presente;
- `public.get_refill_productivity_kpi` presente in `pg_proc`;
- `refills_productivity_created_operator_idx` presente;
- `refills_productivity_machine_created_idx` presente.

### Firme RPC

Verifiche catalogo:

```text
get_refill_productivity_kpi(
  p_period_days integer,
  p_timezone text,
  p_theoretical_work_hours_per_day numeric
)
```

```text
perform_refill_consumable(
  p_machine_id uuid,
  p_type consumable_type
)
```

### Chiamata KPI admin

E stata simulata una chiamata come utente admin usando claim locali di sessione in una transazione rollback-only.

Risultato:

- payload JSON di tipo `object`;
- chiave `summary` presente;
- chiave `operators` presente;
- `period.days = 7`;
- `period.timezone = Europe/Rome`.

E stata verificata anche la chiamata con parametri nominati nello stesso set dell'errore PostgREST:

```sql
public.get_refill_productivity_kpi(
  p_period_days := 7,
  p_theoretical_work_hours_per_day := 6,
  p_timezone := 'Europe/Rome'
)
```

Risultato: payload JSON valido.

### Registrazione migration

La migration risulta registrata in:

`supabase_migrations.schema_migrations`

Con:

- `name = 'refill_productivity_kpi'`
- `version = '20260825124730'`

## Preparazione dati test

Per testare il KPI, sono state portate a `0%` le macchine assegnate all'operatore:

`operatore.pilot@ic01.test`

Risultato finale dalla vista usata dall'app:

| Campo | Valore |
| --- | ---: |
| Macchine effettive | 18 |
| Consumabili effettivi | 18 |
| Consumabili con `current_units = 0` | 18 |
| Consumabili con `fill_percent = 0` | 18 |
| Capacita totale refillabile | 4001 |

Questo consente di fare refill dall'app operatore e generare record KPI reali.

## Come testare da app

1. Accedere come `operatore.pilot@ic01.test`.
2. Aprire le macchine assegnate.
3. Verificare che risultino da refillare.
4. Eseguire refill su almeno una macchina.
5. Accedere come admin.
6. Aprire la Dashboard Admin.
7. Controllare card `KPI produttivita refill`.

Per vedere anche la metrica di produttivita osservata, fare almeno due refill nello stesso giorno con lo stesso operatore, perche la finestra osservata richiede un primo e un ultimo refill distinti.

## Query utili di verifica

### Verifica colonne

```sql
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'refills'
  and column_name in (
    'consumable_type',
    'previous_units',
    'capacity_units',
    'refilled_units',
    'snapshot_metadata'
  )
order by column_name;
```

### Verifica funzione KPI

```sql
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  p.proacl::text as grants
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_refill_productivity_kpi';
```

### Verifica refill recenti con snapshot

```sql
select
  created_at,
  machine_id,
  operator_id,
  consumable_type,
  previous_units,
  capacity_units,
  refilled_units,
  snapshot_metadata
from public.refills
where refilled_units is not null
order by created_at desc
limit 20;
```

### Verifica KPI come admin

Da SQL editor con sessione admin reale o tramite client autenticato:

```sql
select public.get_refill_productivity_kpi(
  p_period_days := 7,
  p_timezone := 'Europe/Rome',
  p_theoretical_work_hours_per_day := 6
);
```

## Rollback logico

Non e stato creato rollback automatico. La migration e additiva sui dati e sostitutiva sulle RPC.

In caso di problema sul refill operativo, il rollback piu prudente e:

1. ripristinare la definizione precedente di `perform_refill_consumable`;
2. mantenere le colonne aggiunte in `refills`, perche non sono distruttive;
3. lasciare o revocare temporaneamente `get_refill_productivity_kpi` a seconda dell'errore;
4. eseguire `notify pgrst, 'reload schema';`.

E sconsigliato eliminare colonne o dati refill generati, per non perdere eventi gia raccolti.

## Note operative

- La dashboard puo mostrare dati insufficienti finche non vengono generati refill nuovi con `refilled_units`.
- I 29 refill storici pre-migration non hanno quantita refillata.
- Premere refill su un consumabile gia pieno non crea evento KPI.
- La produttivita osservata richiede almeno due refill nella stessa giornata operativa.
- La produttivita teorica usa il default di 6 ore/giorno, configurabile via parametro RPC.

