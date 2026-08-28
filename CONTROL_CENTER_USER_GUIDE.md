# MAGMA Control Center - Guida Utente

## Scopo

Il MAGMA Control Center e' il backoffice tecnico interno per monitorare la
flotta IC01, verificare lo stato dei device, leggere eventi diagnostici e
creare job di comando supportati dal firmware.

Questa pagina non sostituisce il backoffice cliente/amministratore. E' pensata
per il team MAGMA/Foresight e deve essere usata solo da account interni
abilitati.

## Accesso

L'accesso avviene dalla normale pagina di login dell'app.

1. Apri la pagina di login.
2. Inserisci l'email e la password dell'account interno.
3. Se l'account ha ruolo `internal_admin`, l'app apre automaticamente
   `/control-center`.

Non esiste una password speciale nel codice dell'app. Il permesso dipende dal
profilo Supabase associato all'utente autenticato.

Se dopo il login non arrivi al Control Center, le cause piu' probabili sono:

- l'utente Supabase Auth non esiste;
- il profilo collegato non ha ruolo `internal_admin`;
- la sessione nel browser/app e' vecchia e va rifatto logout/login;
- il backend non ha ancora esposto le funzioni RPC del Control Center.

## Navigazione

Il Control Center ha quattro sezioni principali:

- `Overview`: sintesi salute flotta e stato backend.
- `Devices`: elenco device, filtri e accesso al dettaglio.
- `Events`: ricerca eventi tecnici e diagnostici.
- `Diagnostics`: creazione di job di comando supportati.

Su desktop la navigazione e' laterale. Su mobile o tablet compatto puo'
apparire come navigazione inferiore.

Usa il pulsante di aggiornamento per ricaricare i dati della sezione corrente.
I dati non rappresentano una connessione diretta in tempo reale al device:
sono derivati da telemetrie, eventi, sessioni BLE osservate e sincronizzazioni
registrate in Supabase.

## Overview

La sezione `Overview` mostra lo stato complessivo della flotta.

### Fleet Health

I contatori principali sono:

- `Device totali`: numero totale di device registrati.
- `Healthy`: device senza condizioni critiche note.
- `Warning`: device con warning, calibrazione mancante/non valida o segnali da
  verificare.
- `Degraded`: device con condizione degradata o piu' errori recenti.
- `Offline`: device senza contatto osservato oltre la soglia prevista.
- `Never connected`: device registrato ma mai osservato tramite telemetria,
  evento o sessione.
- `Calibration missing`: device con calibrazione mancante, richiesta o non
  valida.
- `Firmware outdated`: indicatore disponibile solo quando esiste un catalogo
  versioni firmware confrontabile. Se manca, viene mostrato `Not available`.

### Stati device

Gli stati sono calcolati con queste regole operative:

- `HEALTHY`: il device ha contatti recenti e non risultano warning, errori o
  problemi di calibrazione.
- `WARNING`: sono presenti warning recenti oppure calibrazione `missing`,
  `invalid` o `required`.
- `DEGRADED`: il device segnala stato degradato o ha accumulato almeno 3 errori
  o eventi critici nelle ultime 24 ore.
- `OFFLINE`: l'ultimo contatto osservato e' piu' vecchio della soglia di
  offline, attualmente 7 giorni.
- `NEVER CONNECTED`: non esiste ancora nessun contatto osservato.

`OFFLINE` non significa necessariamente hardware guasto. Significa che il
backend non ha visto contatti recenti.

### System Health

Il pannello `System Health` mostra:

- `Database/backend`: stato generale dei dati disponibili lato Supabase.
- `Edge Functions`: stato osservabile delle funzioni backend.
- `BLE success rate 24h`: percentuale di sessioni BLE riuscite nelle ultime 24
  ore, se disponibili.
- `Error rate 24h`: volume o tasso di errori recenti.
- `App versions`: versioni app osservate nei dati.
- `Latest event received`: ultimo evento tecnico ricevuto.

Quando un dato non e' ancora strumentato o non e' presente, la UI mostra
`Not available`.

### Attention Required

`Attention Required` elenca i device che richiedono priorita' operativa. Apri
un device da questa lista per entrare direttamente nel dettaglio.

### Latest Events

`Latest Events` mostra gli eventi tecnici piu' recenti. Cliccando un evento si
apre il dettaglio con severita', sorgente, sommario e payload JSON.

## Devices

La sezione `Devices` e' la vista principale per cercare e confrontare i device.

### Filtri disponibili

- `Search`: cerca per device ID, seriale, cliente, sede, citta', macchina,
  firmware o ultimo operatore.
- `Health`: filtra per stato salute.
- `Calibration`: filtra per `Valid`, `Missing`, `Invalid` o `Not available`.
- `Firmware`: filtra per versione firmware esatta.
- `Sort`: ordina per ultimo contatto, health o device ID.

### Colonne della tabella

- `Device`: identificativo del device.
- `Client`: cliente associato.
- `Site`: sede associata.
- `Machine`: macchina collegata.
- `Health`: stato salute calcolato.
- `Last contact`: ultimo contatto osservato.
- `Firmware`: versione firmware nota.
- `Calibration`: stato calibrazione.
- `Last operator/app`: ultimo operatore o versione app osservata.
- `Warnings`: conteggio warning/errori e segnalazioni di calibrazione.

Su schermi piccoli la tabella viene sostituita da card compatte. Tocca una
riga o una card per aprire il dettaglio device.

## Dettaglio Device

La pagina di dettaglio mostra tutte le informazioni disponibili per un singolo
device.

### Identity

Mostra device ID, serial number, hardware revision, macchina, cliente e sede.
Se il device non e' ancora collegato a una macchina o a un cliente, vedrai
`Not linked`.

### Health

Mostra stato salute, ultimo contatto, ultimo evento, warning nelle ultime 24
ore ed errori nelle ultime 24 ore.

### Firmware

Mostra versione installata e revisione hardware. Alcune informazioni di build
possono comparire come `Not available` fino a quando il firmware non le invia
in modo strutturato.

### Calibration

Mostra stato calibrazione, data ultima calibrazione, operatore e disponibilita'
dei parametri. Se i parametri non sono sincronizzati, il campo rimane
`Not available`.

### Connectivity

Mostra le sessioni BLE osservate, quando l'app le invia al backend:

- inizio sessione;
- risultato;
- durata;
- motivo di disconnessione o codice errore;
- operatore/versione app.

Se compare `BLE session data not available`, significa che il backend non ha
ancora ricevuto sessioni BLE osservate per quel device.

### Latest Sensor Data

Mostra l'ultimo snapshot sensori disponibile. Al momento il firmware invia
principalmente conteggi e stato: i raw sensor snapshots possono risultare
`Not available` finche' non saranno supportati dal firmware.

### Command Audit

Mostra i job di comando creati per il device, con stato, data richiesta,
eventuali date di consegna/completamento ed errore.

### Event Timeline

Mostra la timeline eventi del device. Apri un evento per leggere dettaglio,
severita' e payload JSON.

## Events

La sezione `Events` serve per cercare eventi tecnici e diagnostici.

Filtri disponibili:

- `Device UUID`: limita la ricerca a un device specifico.
- `Event type`: cerca un tipo evento specifico.
- `Severity`: `Info`, `Warning`, `Error`, `Critical` o `All`.
- `Limit`: massimo numero di risultati, tra 50, 100, 250 e 500.

Dopo aver compilato un filtro testuale, premi `Filtra` o invio nel campo.

Le severita' vanno lette cosi':

- `Info`: evento informativo.
- `Warning`: condizione da controllare.
- `Error`: errore applicativo, firmware, BLE o backend.
- `Critical`: condizione critica che richiede priorita'.

Il payload JSON e' utile per diagnosi tecniche. Se il contenuto non e' chiaro,
va passato a chi gestisce firmware/backend insieme a device ID, orario e tipo
evento.

## Diagnostics

La sezione `Diagnostics` crea job di comando per un device.

Il flusso e' asincrono:

```text
Control Center -> Supabase device_commands -> app operatore o polling device
-> ESP32 -> conferma -> Supabase -> Control Center
```

Quando crei un job, non stai inviando un comando diretto dal browser al device.
Il comando resta in coda finche' l'app operatore o il device non lo legge e lo
gestisce.

### Target Device

Scegli il device dal menu `Device`. La label mostra device ID, macchina e
cliente quando disponibili.

### Supported Commands

La UI mostra solo i comandi supportati dal backend e dal firmware corrente.
Nel MVP il comando operativo supportato e':

- `set_products`: job di scrittura che imposta una configurazione prodotti
  predefinita.

Il pulsante `Crea job` crea il comando per il device selezionato.

Usalo con cautela: `set_products` e' una scrittura di configurazione, non una
lettura diagnostica.

### Unsupported Commands

I comandi non ancora supportati sono mostrati come `unsupported`. Non devono
essere forzati manualmente. Le lacune firmware note sono documentate in
`CONTROL_CENTER_FIRMWARE_GAPS.md`.

### Stati dei command job

Gli stati piu' importanti sono:

- `queued`: job creato, in attesa che app/device lo legga.
- `delivered_to_app`: job consegnato all'app operatore.
- `sent_to_device`: job inoltrato verso il device.
- `completed`: job completato.
- `failed`: job fallito.
- `expired`: job scaduto.
- `unsupported`: comando non supportato.
- `cancelled`: job annullato.

Evita di creare piu' job identici sullo stesso device senza verificare prima
lo stato del job precedente.

## Troubleshooting

### Dopo il login non entro nel Control Center

Verifica che l'account sia autenticato e che il profilo Supabase abbia ruolo
`internal_admin`. Dopo una modifica ruolo, fai logout e login per ricaricare la
sessione e il routing.

### Vedo "Accesso negato"

Il backend ha risposto come se l'utente non fosse autorizzato. La causa piu'
probabile e' un ruolo profilo non corretto o una sessione non aggiornata.

### Vedo "Could not find the function ... in the schema cache"

Il frontend sta chiamando una funzione RPC che PostgREST non vede nello schema
cache. Di solito significa che la migrazione Supabase non e' stata applicata
correttamente o che lo schema cache deve essere ricaricato.

In questo caso non e' un errore dell'utente finale: va passato al maintainer
tecnico con nome funzione, schermata e orario dell'errore.

### La lista device e' vuota

Possibili cause:

- non ci sono device registrati;
- il profilo non ha ruolo `internal_admin`;
- le policy RLS stanno filtrando i dati;
- la migrazione Control Center non e' allineata all'ambiente Supabase aperto
  dall'app.

### Molti campi mostrano "Not available"

`Not available` significa che il dato non e' presente o non e' ancora
strumentato. Non significa automaticamente malfunzionamento.

Esempi frequenti:

- catalogo firmware non ancora disponibile;
- sessioni BLE non ancora sincronizzate;
- snapshot sensori raw non ancora esposto dal firmware;
- informazioni build firmware non ancora inviate.

### Un device e' offline ma sul campo sembra funzionare

Il Control Center usa l'ultimo contatto osservato dal backend. Se il device
funziona localmente ma non invia dati, il problema puo' essere di rete,
sincronizzazione app, polling o telemetria.

## Checklist operativa

Per una verifica rapida:

1. Apri `Overview` e controlla `Attention Required`.
2. Apri il device in stato `WARNING`, `DEGRADED`, `OFFLINE` o
   `NEVER CONNECTED`.
3. Controlla `Last contact`, `Warnings 24h`, `Errors 24h` e `Calibration`.
4. Leggi `Event Timeline` e apri gli eventi con severita' alta.
5. Se serve un comando, passa a `Diagnostics`, seleziona il device e crea solo
   job supportati.
6. Dopo aver creato un job, torna al dettaglio device e controlla
   `Command Audit`.

## Limiti attuali

I principali limiti del MVP sono:

- niente connessione BLE diretta dal Control Center;
- diagnostiche firmware read-only non ancora disponibili;
- stato online derivato da contatti osservati, non da presenza live;
- catalogo versioni firmware non ancora completo;
- paginazione eventi ancora basata su limite numerico.

Per i gap firmware tecnici consultare `CONTROL_CENTER_FIRMWARE_GAPS.md`.
