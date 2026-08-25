# KPI produttività refill

Il KPI e' disponibile solo nella Dashboard Admin e viene calcolato lato
PostgreSQL dalla RPC `public.get_refill_productivity_kpi`.

## Snapshot refill

La RPC operativa `public.perform_refill_consumable` salva in `public.refills`
lo snapshot del consumabile prima del reset:

- `previous_units`: dosi presenti prima del refill;
- `capacity_units`: capacita' configurata del consumabile;
- `refilled_units`: `capacity_units - previous_units`, solo se positiva;
- `consumable_type`: fattore monitorato.

Gli eventi storici senza `refilled_units` restano validi per il conteggio dei
refill, ma sono esclusi dalle metriche basate sulle dosi. Il client non
ricalcola mai le dosi interrogando lo stato corrente della macchina.

## Definizioni

La giornata operativa viene ricavata da `created_at` in timezone `Europe/Rome`.
I timestamp restano `timestamptz`.

Un `active_refill_day` e' una coppia operatore/giornata con almeno un refill
valido. Il turno teorico e' centralizzato nella RPC come parametro
`p_theoretical_work_hours_per_day`, con default `6`.

Per ogni operatore/giornata:

- `D`: somma delle dosi refillate disponibili;
- `R`: numero di refill validi;
- `first_refill`: primo refill della giornata;
- `last_refill`: ultimo refill della giornata;
- `observed_refill_window`: `last_refill - first_refill`.

Una finestra osservata esiste solo con almeno due refill e timestamp distinti.
Un solo refill non produce produttivita' osservata, per evitare divisioni prive
di significato.

Su periodi multi-giorno, le finestre vengono calcolate per singola giornata e
poi sommate. Non viene mai usato l'intervallo tra il primo e l'ultimo refill
dell'intero periodo.

## Metriche

- `doses_per_theoretical_hour`:
  `total_refilled_doses / (active_refill_days * 6)`.
- `doses_per_observed_hour`:
  dosi delle sole giornate con finestra osservabile divise per la somma delle
  finestre giornaliere osservate.
- `observed_window_utilization`:
  `total_observed_refill_hours / (observable_days * 6)`.
- `theoretical_residual_capacity_hours`:
  `max((observable_days * 6) - total_observed_refill_hours, 0)`.

La UI usa volutamente i termini "finestra refill osservata" e "capacita'
teorica residua": non rappresentano tempo effettivamente lavorato, tempo libero
o tempo risparmiato.

## Confronto periodo precedente

Per il periodo selezionato, la RPC calcola anche il periodo precedente di pari
durata. I delta percentuali sono `NULL` quando il valore precedente e' assente o
zero, cosi' la UI mostra `N/D`/assenza delta invece di percentuali infinite.
