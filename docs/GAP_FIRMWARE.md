# Gap firmware per calibrazione BLE IC01

Audit eseguito il 2026-08-06 su firmware read-only:
`/Users/massimilianoiannucci/Documents/magma/ic-01-firwmare`, branch `main`,
HEAD `54f93a5a176f2523235ac130f238b83705d9aa79`.

## Riepilogo esecutivo

Il firmware contiene una pipeline reale di calibrazione mic + vibrazione e LDR,
ma oggi e' comandabile solo da seriale a caratteri singoli. Non esiste BLE, non
esiste un protocollo stato/risultato/cancel, e non esiste una lettura locale
sicura dell'identita' dispositivo. L'app Flutter puo' pianificare le astrazioni
BLE, ma non puo' implementare o validare il flusso end-to-end finche' i gap
blocker non sono chiusi.

- Blocker: 5
- Alta priorita': 5
- Media priorita': 2

Ordine consigliato:

1. `FW-GAP-001`, `FW-GAP-002`, `FW-GAP-003`
2. `FW-GAP-004`, `FW-GAP-005`
3. `FW-GAP-006`, `FW-GAP-007`, `FW-GAP-008`
4. `FW-GAP-009`, `FW-GAP-010`, `FW-GAP-011`, `FW-GAP-012`

Dipendenze principali:

- `FW-GAP-002` dipende da `FW-GAP-001`.
- `FW-GAP-004` dipende da `FW-GAP-002`.
- `FW-GAP-006` dipende da `FW-GAP-001` e `FW-GAP-003`.
- `FW-GAP-009` dipende da `FW-GAP-002`, `FW-GAP-004` e `FW-GAP-005`.

Definizione di "firmware pronto per integrazione Flutter": l'app mobile riesce a
scansionare il servizio IC01, leggere una identity stabile, verificarla rispetto
a `devices.device_id`, avviare una sessione di calibrazione coerente con
`machines.temperature_mode`, ricevere stato/progresso/risultato, gestire
disconnessione/reconnect, e ricevere conferma che la vecchia calibrazione resta
valida se la nuova fallisce.

## FW-GAP-001 — Servizio BLE IC01 assente

- **Priorità:** blocker
- **Area:** BLE
- **Stato attuale:** il firmware Arduino ESP32 include `WiFi.h`, `HTTPClient`,
  `Preferences`, I2S e Wire, ma nessuna libreria BLE, advertising, GATT service
  o callback. I comandi sono in `handleSerialCommands()`.
- **Problema:** l'app mobile non ha un trasporto locale verso il dispositivo.
- **Impatto software:** `BleTransport` e discovery non sono implementabili contro
  hardware reale.
- **Comportamento richiesto:** advertising BLE IC01, connessione GATT e
  characteristic per info, comandi e notifiche.
- **Contratto proposto:** servizio IC01 proposto, non implementato:
  `9b7e0001-5a3c-4f3b-9d0e-1c0100000001`; `info` read, `control` write,
  `events` notify/indicate.
- **File firmware coinvolti:** `src/main.cpp`, `src/config.h`,
  `platformio.ini`.
- **Funzioni o classi coinvolte:** `setup()`, `loop()`, `handleSerialCommands()`.
- **Modifica suggerita:** aggiungere un modulo BLE separato dalla business logic
  di calibrazione; il main loop deve solo avanzare sensori e stato.
- **Criteri di accettazione:** scan da Android/iOS vede advertising IC01;
  discovery GATT espone caratteristiche documentate; read/write/notify sono
  verificabili con un BLE scanner.
- **Test firmware richiesti:** test hardware ESP32 + telefono; test reconnect;
  test coesistenza Wi-Fi/I2S/IMU.
- **Dipendenze:** nessuna.
- **Decisione necessaria:** scegliere libreria BLE ESP32 Arduino/NimBLE e UUID
  definitivi.
- **Compatibilita:** attenzione a RAM, timing I2S e coesistenza radio Wi-Fi/BLE.

## FW-GAP-002 — API di calibrazione indipendente dal trasporto assente

- **Priorità:** blocker
- **Area:** calibrazione / protocollo
- **Stato attuale:** la calibrazione parte solo da caratteri seriali `I`, `C`,
  `T`, `P`; LDR da `B`, `N`, `R`, `X`. La logica chiama direttamente
  `gMicSensor.startCalibration(...)`.
- **Problema:** non esiste una funzione applicativa riusabile da BLE con
  validazione, stato, risposta e risultato strutturati.
- **Impatto software:** Flutter non puo' avviare, annullare o leggere una
  calibrazione in modo affidabile.
- **Comportamento richiesto:** API firmware interna tipo
  `startCalibrationSession(mode, profile, request_id)`, `cancelCalibration()`,
  `getCalibrationStatus()`, `getCalibrationResult()`.
- **Contratto proposto:** comando `cal.start` con `request_id`, `session_id`,
  `mode`, `profile_set`; evento `cal.status`; evento finale `cal.result`.
- **File firmware coinvolti:** `src/main.cpp`, `src/sensors/MicSensor.cpp`,
  `src/sensors/MicSensor.h`.
- **Funzioni o classi coinvolte:** `handleSerialCommands()`,
  `MicSensor::startCalibration()`, `MicSensor::popCalibrationComplete()`.
- **Modifica suggerita:** estrarre una facciata `CalibrationManager` richiamata
  sia da seriale sia da futuro BLE.
- **Criteri di accettazione:** stesso comportamento da seriale e da BLE; nessuna
  duplicazione dell'algoritmo; errore strutturato se porta aperta o sensori
  mancanti.
- **Test firmware richiesti:** unit test/fake sensor dove possibile; test
  hardware per start/completion/error.
- **Dipendenze:** `FW-GAP-001`.
- **Decisione necessaria:** mantenere seriale legacy come wrapper della nuova
  API.
- **Compatibilita:** non cambiare output seriale diagnostico usato dal team
  firmware.

## FW-GAP-003 — Device identity locale leggibile e stabile assente

- **Priorità:** blocker
- **Area:** device identity
- **Stato attuale:** `kDeviceId = "ic01-esp32-001"` e `kDeviceSecret` sono
  costanti in `src/config.h`; la identity viene inviata come header HTTP, ma non
  e' leggibile localmente via BLE.
- **Problema:** l'app non puo' verificare che il telefono sia collegato al
  device associato alla macchina in `devices.machine_id`.
- **Impatto software:** blocca verifica identity, prevenzione connessione a
  device errato e audit sessione.
- **Comportamento richiesto:** characteristic read-only che restituisce
  `device_id` stabile e firmware version; non usare MAC BLE randomizzabile.
- **Contratto proposto:** `info.read` -> `{device_id, fw_version,
  protocol_version, capabilities}`.
- **File firmware coinvolti:** `src/config.h`, `src/main.cpp`.
- **Funzioni o classi coinvolte:** `sendTelemetry()`, `pollCommands()`.
- **Modifica suggerita:** esporre `kDeviceId` o identity provisionata in NVS su
  characteristic read-only; non esporre secret.
- **Criteri di accettazione:** app legge `device_id` e lo confronta con
  `public.devices.device_id`; BLE MAC non richiesto per associazione.
- **Test firmware richiesti:** test lettura identity dopo reboot e reconnect.
- **Dipendenze:** `FW-GAP-001`.
- **Decisione necessaria:** confermare se `kDeviceId` resta sorgente di verita'
  o viene sostituito da provisioning NVS.
- **Compatibilita:** `machines.code` non deve essere usato come device identity.

## FW-GAP-004 — Stato/progresso/risultato calibrazione non strutturati

- **Priorità:** blocker
- **Area:** protocollo / robustezza
- **Stato attuale:** il firmware stampa log seriali come `Calibrating: COFFEE` e
  `Calibration complete: <id>`, ma non conserva una sessione interrogabile.
- **Problema:** Flutter non puo' mostrare progresso, recuperare stato dopo
  disconnessione o distinguere errori.
- **Impatto software:** blocca UX operatore, retry, reconnect e audit.
- **Comportamento richiesto:** stato interrogabile con percentuale, step,
  istruzione operatore, errore e risultato finale.
- **Contratto proposto:** stati `idle`, `ready`, `collecting_baseline`,
  `waiting_for_dispense`, `collecting_event`, `processing`, `saving`,
  `completed`, `cancelled`, `failed`; eventi notify ordinati con `seq`.
- **File firmware coinvolti:** `src/main.cpp`, `src/sensors/MicSensor.cpp`.
- **Funzioni o classi coinvolte:** `loop()`, `MicSensor::update()`,
  `MicSensor::popCalibrationComplete()`.
- **Modifica suggerita:** introdurre `CalibrationSessionState` persistente in RAM
  e query `cal.status`.
- **Criteri di accettazione:** stato recuperabile in qualunque momento; dopo
  reconnect l'app riceve lo stesso `session_id` e l'ultimo stato.
- **Test firmware richiesti:** disconnessione BLE durante calibrazione,
  completamento, porta aperta, sensore IMU assente.
- **Dipendenze:** `FW-GAP-002`.
- **Decisione necessaria:** decidere se usare notify o indicate per eventi
  critici.
- **Compatibilita:** logging seriale puo' restare diagnostico, ma non deve essere
  l'unica API.

## FW-GAP-005 — Persistenza non atomica/versionata per uso remoto

- **Priorità:** blocker
- **Area:** persistenza
- **Stato attuale:** profili mic sono salvati in NVS namespace `mic_profiles`
  con key `pN`; vibrazioni in `vib_profiles`; LDR in `ldr_cal`. Non risultano
  schema version, checksum, staging o commit atomico.
- **Problema:** una calibrazione nuova non ha garanzie esplicite di rollback,
  integrita' e compatibilita' dopo update firmware.
- **Impatto software:** l'app non puo' promettere che la vecchia calibrazione
  resti valida se la nuova fallisce o se la flash contiene dati corrotti.
- **Comportamento richiesto:** staging temporaneo, validazione, commit atomico,
  rollback, schema version e checksum.
- **Contratto proposto:** `cal.result` deve includere `calibration_version`,
  `profile_set_hash`, `committed: true`, `previous_preserved: true`.
- **File firmware coinvolti:** `src/sensors/MicSensor.cpp`, `src/main.cpp`.
- **Funzioni o classi coinvolte:** `MicSensor::saveProfile_()`,
  `MicSensor::setProfileEvents()`, `saveVibProfile()`, `saveVibThreshold()`.
- **Modifica suggerita:** salvare nuovi profili in namespace/key temporanei e
  promuoverli solo dopo validazione completa mic + vib + threshold.
- **Criteri di accettazione:** power loss/failure non invalida profilo
  precedente; firmware rileva dati corrotti e segnala errore.
- **Test firmware richiesti:** test reboot durante salvataggio, NVS corrotta,
  nuova calibrazione fallita.
- **Dipendenze:** `FW-GAP-002`, `FW-GAP-004`.
- **Decisione necessaria:** formato/versione dello schema profili.
- **Compatibilita:** migrazione da profili NVS legacy.

## FW-GAP-006 — Sicurezza BLE e provisioning non definiti

- **Priorità:** alta
- **Area:** sicurezza
- **Stato attuale:** backend device usa HMAC con `kDeviceSecret`; il secret e'
  hardcoded nel firmware e non deve essere copiato nell'app. Non esistono BLE
  pairing, bonding, maintenance mode o challenge-response.
- **Problema:** un comando BLE non autenticato potrebbe avviare calibrazione o
  leggere dati operativi.
- **Impatto software:** l'app non puo' rispettare il trust model richiesto senza
  primitive firmware.
- **Comportamento richiesto:** pairing/bonding o finestra fisica di
  manutenzione; nessun secret in chiaro; autorizzazione utente lato app +
  controllo local proximity lato device.
- **Contratto proposto:** pilot: BLE accessibile solo in maintenance window
  attivata fisicamente; industrializzazione: LE Secure Connections + bonding,
  allowlist/provisioning e rotazione secret backend separata.
- **File firmware coinvolti:** `src/config.h`, `src/main.cpp`.
- **Funzioni o classi coinvolte:** `hmacSha256Hex()`, `sendTelemetry()`,
  `pollCommands()`.
- **Modifica suggerita:** separare secret backend da BLE; evitare log di secret;
  aggiungere stato `maintenance_allowed`.
- **Criteri di accettazione:** app non conosce `device_secret`; BLE rejecta
  comandi fuori maintenance window; log non contengono secret.
- **Test firmware richiesti:** tentativo comando non autorizzato, bonded device,
  reset pairing.
- **Dipendenze:** `FW-GAP-001`, `FW-GAP-003`.
- **Decisione necessaria:** livello security pilot vs industrializzazione.
- **Compatibilita:** non rompere HMAC HTTPS esistente.

## FW-GAP-007 — Contratto hot/cold non mappato nel firmware

- **Priorità:** alta
- **Area:** calibrazione
- **Stato attuale:** profili reali sono `IDLE`, `COFFEE`, `CAPPUCCINO`,
  `POWDERS`. Nel firmware non esiste `hot`/`cold` e non esistono finestre o
  sensori diversi per cold.
- **Problema:** `machines.temperature_mode` non puo' guidare automaticamente la
  procedura firmware.
- **Impatto software:** Flutter non puo' derivare istruzioni e profili necessari
  dal tipo macchina.
- **Comportamento richiesto:** capability firmware che dichiara profili richiesti
  per `hot` e `cold`, o errore `unsupported_mode`.
- **Contratto proposto:** `capabilities.calibration_modes = {hot: [...],
  cold: [...]}`; `cal.start.mode` ammesso solo se supportato.
- **File firmware coinvolti:** `src/sensors/MicSensor.h`, `src/main.cpp`,
  `src/config.h`.
- **Funzioni o classi coinvolte:** `MicProfileId`, `profileName()`,
  `hasRequiredProfiles()`.
- **Modifica suggerita:** definire `profile_set` per hot/cold senza modificare
  algoritmo detection.
- **Criteri di accettazione:** device risponde a `mode=hot` e `mode=cold` con
  profili/istruzioni o errore strutturato.
- **Test firmware richiesti:** calibrazione hot completa; cold se supportata su
  hardware reale.
- **Dipendenze:** `FW-GAP-002`, decisione prodotto.
- **Decisione necessaria:** significato operativo di cold nel firmware.
- **Compatibilita:** mantenere profili beverage legacy se usati da telemetria.

## FW-GAP-008 — Comandi seriali non strutturati e non riusabili come protocollo

- **Priorità:** alta
- **Area:** protocollo
- **Stato attuale:** protocollo seriale e' una lista di char senza request id,
  payload, ack, errore machine-readable o idempotenza.
- **Problema:** non e' possibile riutilizzarlo direttamente sopra BLE in modo
  robusto.
- **Impatto software:** Flutter dovrebbe fare parsing fragile di log, cosa da
  evitare.
- **Comportamento richiesto:** formato messaggi stabile, preferibilmente JSON
  compatto o CBOR, con `type`, `command`, `request_id`, `session_id`, `seq`.
- **Contratto proposto:** characteristic `control` riceve JSON line UTF-8;
  `events` notifica JSON line; payload massimo < MTU negoziato o chunking.
- **File firmware coinvolti:** `src/main.cpp`.
- **Funzioni o classi coinvolte:** `handleSerialCommands()`, `printProfileLine()`.
- **Modifica suggerita:** seriale legacy resta per manutenzione, nuovo protocollo
  strutturato alimenta sia BLE sia eventuale seriale avanzata.
- **Criteri di accettazione:** ogni comando ha ack o errore; duplicati gestiti
  con `request_id`.
- **Test firmware richiesti:** comandi duplicati, payload invalido, ordine eventi.
- **Dipendenze:** `FW-GAP-002`.
- **Decisione necessaria:** JSON vs CBOR.
- **Compatibilita:** non eliminare comandi seriali esistenti.

## FW-GAP-009 — Risultato calibrazione insufficiente per audit backend

- **Priorità:** alta
- **Area:** protocollo / test
- **Stato attuale:** il risultato seriale stampa profilo e ID numerico; non
  include session id, mode, firmware/protocol version, parametri sintetici,
  hash, durata o errori.
- **Problema:** Supabase non puo' registrare una sessione idempotente e
  verificabile.
- **Impatto software:** blocca `calibration_sessions` affidabile e sync offline.
- **Comportamento richiesto:** risultato finale strutturato con metadati.
- **Contratto proposto:** `cal.result = {session_id, request_id, device_id,
  machine_mode, status, started_at_ms, completed_at_ms, fw_version,
  protocol_version, profile_set_hash, metrics_summary, error}`.
- **File firmware coinvolti:** `src/main.cpp`, `src/sensors/MicSensor.h`.
- **Funzioni o classi coinvolte:** `MicSensor::popCalibrationComplete()`,
  `printProfileLine()`.
- **Modifica suggerita:** produrre un DTO risultato separato dai log.
- **Criteri di accettazione:** app puo' salvare risultato e riprovare sync senza
  duplicati.
- **Test firmware richiesti:** successo, fallimento, cancel, reconnect.
- **Dipendenze:** `FW-GAP-004`, `FW-GAP-005`.
- **Decisione necessaria:** quali parametri possono essere esposti senza
  compromettere IP/diagnostica.
- **Compatibilita:** non alterare algoritmo di classificazione.

## FW-GAP-010 — Associazione backend/device non validabile end-to-end

- **Priorità:** alta
- **Area:** device identity / sicurezza
- **Stato attuale:** tabella remota `devices` esiste con `device_id` unique e
  `machine_id`, ma al momento non ci sono righe; firmware contiene un
  `kDeviceId` hardcoded.
- **Problema:** non c'e' prova che il device reale sia provisionato e associato
  alla macchina corretta.
- **Impatto software:** blocca test hardware completo con verifica backend.
- **Comportamento richiesto:** provisioning device con `device_id` uguale a
  quello letto via BLE e `machine_id` valorizzato.
- **Contratto proposto:** `info.device_id` deve combaciare con
  `public.devices.device_id`; app carica `devices.machine_id = machine.id`.
- **File firmware coinvolti:** `src/config.h`, `supabase_device_schema.sql`.
- **Funzioni o classi coinvolte:** `sendTelemetry()`, `pollCommands()`.
- **Modifica suggerita:** definire procedura firmware/manufacturing per identity
  non hardcoded per lotto.
- **Criteri di accettazione:** device reale appare in Supabase dev associato alla
  macchina di test; app rifiuta mismatch.
- **Test firmware richiesti:** test identity su piu' dispositivi.
- **Dipendenze:** `FW-GAP-003`.
- **Decisione necessaria:** owner provisioning e formato label/QR.
- **Compatibilita:** preservare endpoint HMAC attuali.

## FW-GAP-011 — Errori e timeout operatore non completi

- **Priorità:** media
- **Area:** robustezza
- **Stato attuale:** porta aperta blocca/ferma alcune operazioni; IMU assente
  viene loggato; non ci sono codici errore strutturati per app.
- **Problema:** UX Flutter non puo' mostrare istruzioni precise o retry sicuri.
- **Impatto software:** gestione errori rimane ambigua.
- **Comportamento richiesto:** errori codificati: `door_open`,
  `missing_profiles`, `imu_missing`, `mic_read_failed`, `busy`, `unsupported`,
  `timeout`, `storage_error`, `unauthorized`.
- **Contratto proposto:** `cal.error` con `code`, `message_key`, `retryable`,
  `recover_action`.
- **File firmware coinvolti:** `src/main.cpp`, `src/sensors/MicSensor.cpp`,
  `src/sensors/AccelSensor.cpp`.
- **Funzioni o classi coinvolte:** `startListening()`, `loop()`,
  `MicSensor::computeFeatures_()`, `AccelSensor::begin()`.
- **Modifica suggerita:** mappare tutti i fail path a enum errori.
- **Criteri di accettazione:** ogni fallimento restituisce un codice stabile.
- **Test firmware richiesti:** scenari porta aperta, IMU non presente, payload
  invalido, busy.
- **Dipendenze:** `FW-GAP-004`.
- **Decisione necessaria:** catalogo messaggi tradotti lato app.
- **Compatibilita:** log seriali possono continuare a stampare testo libero.

## FW-GAP-012 — Test firmware di contratto BLE mancanti

- **Priorità:** media
- **Area:** test
- **Stato attuale:** non sono presenti test automatici o script read-only di
  validazione protocollo; il repo contiene `.pio` preesistente ma non e' stato
  compilato durante l'audit.
- **Problema:** integrazione Flutter rischia regressioni non visibili.
- **Impatto software:** mock e hardware test non hanno una fonte verificabile.
- **Comportamento richiesto:** checklist/test contract per advertising, GATT,
  stato, errori, persistenza e reconnect.
- **Contratto proposto:** golden JSON/eventi per comandi principali e test
  hardware manuale ripetibile.
- **File firmware coinvolti:** nuovo materiale da creare dal team firmware, non
  in questo audit.
- **Funzioni o classi coinvolte:** futura API BLE e `CalibrationManager`.
- **Modifica suggerita:** aggiungere test nel repo firmware a cura firmware team.
- **Criteri di accettazione:** prima del handoff Flutter esiste report test
  hardware con firmware version e protocol version.
- **Test firmware richiesti:** suite contract + test manuale end-to-end.
- **Dipendenze:** tutti i gap BLE/protocollo.
- **Decisione necessaria:** tooling di test BLE.
- **Compatibilita:** nessuna sul comportamento runtime.

## Matrice finale

| Gap | Priorità | Blocca Flutter | Blocca test hardware | Dipende da | Owner |
|---|---|---:|---:|---|---|
| FW-GAP-001 | blocker | si | si | - | Firmware team |
| FW-GAP-002 | blocker | si | si | FW-GAP-001 | Firmware team |
| FW-GAP-003 | blocker | si | si | FW-GAP-001 | Firmware team |
| FW-GAP-004 | blocker | si | si | FW-GAP-002 | Firmware team |
| FW-GAP-005 | blocker | si | si | FW-GAP-002, FW-GAP-004 | Firmware team |
| FW-GAP-006 | alta | si | si | FW-GAP-001, FW-GAP-003 | Firmware team |
| FW-GAP-007 | alta | si | si | FW-GAP-002 | Firmware team |
| FW-GAP-008 | alta | si | si | FW-GAP-002 | Firmware team |
| FW-GAP-009 | alta | si | si | FW-GAP-004, FW-GAP-005 | Firmware team |
| FW-GAP-010 | alta | si | si | FW-GAP-003 | Firmware team |
| FW-GAP-011 | media | parziale | si | FW-GAP-004 | Firmware team |
| FW-GAP-012 | media | no | si | tutti | Firmware team |
