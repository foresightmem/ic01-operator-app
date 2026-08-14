# Stato reale firmware IC01 — aggiornamento 2026-08-14

Questo documento raccoglie lo stato effettivamente implementato nel firmware
ESP32 dopo l’analisi iniziale e la realizzazione del protocollo BLE applicativo.

## Riepilogo esecutivo

Il progetto non è più allo stato “gap analysis only”: il firmware ha ricevuto
l’implementazione di un protocollo BLE applicativo reale, con sessioni di
calibrazione, stato strutturato, gestione errori e persistenza sicura dei
profili.

In sintesi, oggi il firmware:

- espone un servizio BLE IC01 con characteristic per info, control e events
- riceve comandi JSON su BLE e li interpreta in modo strutturato
- supporta avvio, stato, cancellazione e risultato di calibrazione
- blocca i comandi di calibrazione fuori finestra di manutenzione
- gestisce mode `hot` / `cold` con mapping e errore `unsupported_mode`
- restituisce eventi `cal.status`, `cal.error` e `cal.result`
- salva i profili in modo versionato e verificabile con checksum
- preserva il profilo precedente in caso di write fallita o sessione non
  completata
- compila correttamente con PlatformIO

Il lavoro ancora necessario riguarda la validazione hardware reale sul modulo
ESP32, l'implementazione del flusso BLE nell'app Flutter e i passaggi di
hardening di sicurezza/produzione.

---

## 1. Cosa è stato implementato

### 1.1 Servizio BLE IC01

Il firmware espone un servizio BLE con UUID definiti e già usati in codice:

- servizio: `9B7E0001-5A3C-4F3B-9D0E-1C0100000001`
- info: `9B7E0002-5A3C-4F3B-9D0E-1C0100000001`
- control: `9B7E0003-5A3C-4F3B-9D0E-1C0100000001`
- events: `9B7E0004-5A3C-4F3B-9D0E-1C0100000001`

La logica BLE è integrata in `src/main.cpp` con:

- advertising del servizio IC01
- GATT service + characteristic
- callback di RX per il control characteristic
- notify del characteristic events
- read dell'ultimo payload events per facilitare test manuale con nRF Connect

### 1.2 Protocollo applicativo JSON

Il firmware interpreta comandi JSON e produce eventi JSON, con il seguente
modello logico:

- `info`
- `cal.status`
- `cal.start`
- `cal.cancel`
- `unsupported_command`

I payload sono un JSON UTF-8, con campi come:

- `command`
- `request_id` come stringa opaca, tipicamente UUID lato app
- `session_id` come stringa opaca, tipicamente UUID lato app
- `mode`
- `profile_set`

La parsing viene fatta con `deserializeJson()` e la risposta è generata in modo
uniforme via `emitBleEvent_()`.

Durante i test manuali, ogni payload evento viene anche stampato sul monitor
seriale con prefisso `BLE EVENT:` per verificare il JSON completo quando la UI
del tool BLE mostra solo un'anteprima.

### 1.3 Sessione di calibrazione reali

Abbiamo introdotto una sessione BLE attiva in RAM:

- `gBleSession.active`
- `gBleSession.status`
- `gBleSession.progress`
- `gBleSession.lastMessage`
- `gBleSession.lastError`
- `gBleSession.sessionId`
- `gBleSession.requestId`
- `gBleSession.requestIdCounter`

Questo consente di:

- iniziare una calibrazione da comando BLE
- leggere lo stato corrente da `cal.status`
- annullare una sessione con `cal.cancel`, fermando anche la calibrazione
  interna del sensore
- trasmettere progresso durante la calibrazione
- chiudere la sessione con `cal.result`

### 1.4 Gestione di maintenance mode

Il firmware blocca i comandi di calibrazione se non è attiva la finestra di
manutenzione.

La chiave usata è il pin GPIO0 (BOOT button su molte schede ESP32):

- `kMaintenanceEnablePin = 0`
- logic: il livello raw di GPIO0 non abilita direttamente la maintenance;
  tenere premuto BOOT per circa 1.5 secondi apre una finestra maintenance
  temporanea di 10 minuti
- da monitor seriale, `m` o `M` abilita/disabilita manualmente la maintenance
  mode; `U` resta riservato al mute degli eventi
- la characteristic `info` aggiorna `maintenance_enabled` anche sulle read
  dirette, non solo tramite comando JSON `info`

Quando la maintenance mode non è attiva, viene generato un errore strutturato:

- `error = "maintenance_required"`
- `retryable = true`
- `recover_action = "enable_maintenance"`

Questo implementa il guardrail richiesto per evitare avvii non autorizzati di
calibrazione via BLE.

Nota di validazione: il blocco trovato durante il test era dovuto a due problemi
 firmware. `M` veniva intercettato dal ramo `m/M` di mute logging, quindi il
toggle maintenance non veniva mai raggiunto. Inoltre `request_id` e `session_id`
venivano convertiti in numeri, mentre il contratto li tratta come stringhe/UUID.
La correzione rende `m/M` entrambi toggle maintenance, sposta il mute eventi su
`U` e preserva gli identificativi BLE come stringhe opache.

### 1.5 Mappatura mode hot/cold

Il firmware ora risolve correttamente i mode supportati:

- `hot` o `coffee` -> profile `kProfileCoffee`
- `cold` o `idle` -> profile `kProfileIdle`
- se passato un mode non supportato, ritorna `unsupported_mode`

La risposta di errore include:

- `retryable = false`
- `recover_action = "choose_supported_mode"`

### 1.6 Eventi standardizzati

Abbiamo implementato il contratto di eventi BLE con payload di tipo:

- `cal.status`
- `cal.error`
- `cal.result`
- `device.info`

Esempio di eventi:

```json
{
  "type": "cal.status",
  "status": "collecting_baseline",
  "seq": 12,
  "request_id": "req-003",
  "session_id": "42",
  "progress": 0.15,
  "message": "calibration_started"
}
```

```json
{
  "type": "cal.error",
  "status": "failed",
  "seq": 13,
  "request_id": "req-003",
  "session_id": "42",
  "error": "unsupported_mode",
  "retryable": false,
  "recover_action": "choose_supported_mode"
}
```

### 1.7 Risultato di calibrazione strutturato

La funzione `emitBleCalibrationResult_()` produce un payload finale con metadati
utili per backend e futura app, tra cui:

- `type = "cal.result"`
- `status = "completed"`
- `device_id`
- `mode`
- `profile_set`
- `calibration_version`
- `committed`
- `previous_preserved`
- `started_at_ms`
- `completed_at_ms`
- `fw_version`
- `protocol_version`
- `profile_valid`
- `metrics_summary`

Se la sessione termina senza un profilo valido, per esempio durante test senza
periferiche di acquisizione collegate, il risultato finale resta `cal.result` ma
viene marcato come fallito:

- `status = "failed"`
- `committed = false`
- `profile_valid = false`
- `error = "invalid_profile"`
- `recover_action = "check_mic_signal_and_retry"`

### 1.8 Persistenza sicura dei profili

Ho fatto un passaggio importante sulla persistenza NVS:

- schema versionato con `kProfileStorageSchemaVersion = 1`
- validazione del profilo caricato prima di usarlo
- preservazione del profilo precedente in caso di salvataggio non riuscito
- gestione di backup/staged write per evitare corruzione totale del profilo
- logica di salvataggio controllata prima del commit

Questo va nella direzione richiesta dal gap originale per evitare che una nuova
calibrazione invalida il profilo precedente in modo non sicuro.

### 1.9 Robustezza di error handling

La funzione `emitBleCalibrationError_()` mappa i principali errori in codice
strutturato, tra cui:

- `door_open`
- `unsupported_mode`
- `maintenance_required`
- `busy`
- `timeout`
- `storage_error`
- `invalid_profile`

Ogni errore viene emesso con:

- `error`
- `message`
- `retryable`
- `recover_action`

---

## 2. Contratto BLE attuale

### 2.1 Comandi supportati

| Comando      | Payload                                                  | Effetto                    |
| ------------ | -------------------------------------------------------- | -------------------------- |
| `info`       | `{ command, request_id, session_id }`                    | ritorna device info        |
| `cal.status` | `{ command, request_id, session_id }`                    | ritorna stato attuale      |
| `cal.start`  | `{ command, request_id, session_id, mode, profile_set }` | avvia calibrazione         |
| `cal.cancel` | `{ command, request_id, session_id }`                    | cancella sessione corrente |
| altri        | —                                                        | `unsupported_command`      |

### 2.2 Risposte/notify attese

- `device.info` -> payload info device
- `cal.status` -> stato sessione
- `cal.error` -> errore strutturato
- `cal.result` -> risultato finale

### 2.3 Esempio payload info

```json
{
  "device_id": "ic01-esp32-001",
  "fw_version": "0.2.0",
  "protocol_version": "1.0.0",
  "maintenance_enabled": true,
  "capabilities": {
    "calibration_modes": ["hot", "cold"],
    "profiles": {
      "hot": "coffee",
      "cold": "idle"
    }
  }
}
```

---

## 3. Sviluppi effettuati rispetto alla baseline originale

Il documento originale descriveva il firmware come ancora privo di un protocollo
BLE applicativo e di una sessione di calibrazione strutturata. Dopo l’analisi
iniziale, il lavoro di implementazione ha portato a una serie di modifiche
concrete in firmware che superano in gran parte quel gap:

- implementazione del servizio BLE IC01 con service e characteristic per
  info/control/events;
- introduzione di un parser JSON per comandi BLE (`info`, `cal.status`,
  `cal.start`, `cal.cancel`);
- realizzazione di una sessione attiva di calibrazione in RAM, con `status`,
  `progress`, `session_id`, `request_id` e ultimo errore;
- aggiunta della finestra di manutenzione via GPIO0 per bloccare i comandi fuori
  contesto autorizzato;
- gestione dei mode `hot`/`cold` con mapping a profili effettivi e risposta
  `unsupported_mode` quando richiesto un profilo non supportato;
- standardizzazione delle notifiche di `cal.status`, `cal.error` e `cal.result`
  con payload JSON;
- emissione di risultati finali con metadata di sessione, firma del profilo,
  versione firmware e metriche di calibrazione;
- miglioramento della persistenza NVS con schema versionato, validazione del
  contenuto e preservazione del profilo precedente in caso di commit fallito;
- introduzione di un modello di errori strutturato con `retryable` e
  `recover_action` per supportare UX e retry nella futura app;
- verifica di build con PlatformIO, che ha prodotto un firmware compilato
  correttamente e pronto per il test hardware manuale.

In altre parole, la baseline originale ha lasciato un backlog teorico; la fase
successiva l’ha trasformato in una prima implementazione funzionale del
protocollo IC01. L'app Flutter non ha ancora il flusso BLE implementato: la
validazione in corso è firmware-first, con nRF Connect o tool BLE equivalente.

---

## 4. Stato del firmware e validazione

#### 4.1 Verifica build eseguita

Ho eseguito la build con PlatformIO:

```bash
cd /Volumes/1TB_Plugin/DEV/Magma/ic-01-firwmare && pio run
```

Risultato verificato:

- exit code: 0
- build completata con successo
- output finale: `Successfully created esp32 image`
- log finale: `BUILD SUCCESS`

Questa verifica conferma che la patch interna e il protocollo BLE attuale
compila correttamente.

### 4.2 Warning rimasti

Durante la build compaiono warning legati a:

- ArduinoJson deprecations (`StaticJsonDocument` / `createNestedObject` /
  `createNestedArray`)
- NimBLE deprecation su `NimBLEService::start()`

Questi warning non bloccano la build, ma sono candidati a cleanup successivo per
ridurre log noise e migliorare la qualità del firmware.

---

## 5. Cosa è ancora da validare sul hardware

La parte di firmware software è pronta per il test reale, ma mancano le
verifiche sul device fisico:

- visibilità del servizio BLE sul telefono Android
- connessione e discovery GATT reali
- lettura della characteristic info
- notify del characteristic events
- comando `cal.start` con manutenzione attiva via `m/M` seriale oppure tenendo
  premuto BOOT per circa 1.5 secondi prima del comando BLE
- risposta `cal.result` o `cal.error` in hardware reale
- comportamento con porta aperta / sessione in corso / timeout / unsupported
  mode

Questa parte va testata ora con nRF Connect o con un tool BLE equivalente. La
app operator potrà essere usata solo dopo l'implementazione del relativo flusso
Flutter.

La checklist operativa dei test manuali è in
`docs/firmware-ble-test-checklist.md`.

---

## 6. Rischi e punti di attenzione

### 6.1 Sicurezza / provisioning

Il firmware ancora usa secret hardcoded e una finestra fisica di manutenzione
come meccanismo di controllo iniziale. Questo è adeguato per il pilot, ma non è
ancora la soluzione definitiva di produzione.

### 6.2 Hardware test

Il firmware è stato validato a livello di compile-time, non ancora a livello di
runtime sul device reale.

### 6.3 App integration

La parte di integrazione con l’app operator non è ancora implementata. Restano da
realizzare: dipendenza BLE, permessi Android/iOS, scan/discovery IC01, parsing
dei payload, gestione di retry/reconnect e UX degli errori.

---

## 7. Stato finale

Lo stato attuale del firmware è:

- BLE applicativo implementato
- robotica di calibrazione parte da protocollo BLE
- manutenzione/guardrail operativo integrato
- persistenza più robusta e versionata
- contratto error/result/status realizzato
- build verificata con successo

L’unico passo fondamentale che manca è la validazione end-to-end sul hardware
reale del firmware via tool BLE manuale. Dopo questo passaggio si può procedere
con implementazione Flutter e finalizzazione del livello di sicurezza/produzione.

---

## 8. Risultato di progetto

Il gap iniziale “servizio BLE assente / protocollo di calibrazione assente /
stato non strutturato” è stato chiuso in modo sostanziale dal punto di vista
firmware. Il progetto è quindi passato dallo stato di analisi a uno stato di
implementazione firmware funzionale, con build verificata e pronta per test
hardware reali. Il gap lato app rimane aperto: il contratto BLE è disponibile,
ma il client Flutter deve ancora essere sviluppato.
