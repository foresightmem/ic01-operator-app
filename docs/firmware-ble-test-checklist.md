# Checklist test firmware BLE IC01

Stato: checklist operativa per validare il contratto BLE firmware prima di
implementare il client Flutter.

## Setup

- Firmware flashato dall'ultima build di `ic-01-firwmare`.
- Monitor seriale aperto a `460800`.
- nRF Connect o tool BLE equivalente.
- Device BLE: `ESP32-Magma`.
- Service IC01: `9B7E0001-5A3C-4F3B-9D0E-1C0100000001`.
- `info`: `9B7E0002-5A3C-4F3B-9D0E-1C0100000001`.
- `control`: `9B7E0003-5A3C-4F3B-9D0E-1C0100000001`.
- `events`: `9B7E0004-5A3C-4F3B-9D0E-1C0100000001`.

## Regole test

- Scrivere i comandi su `control` in formato UTF-8/Text, non HEX.
- Attivare notify su `events`.
- Verificare il JSON completo dal monitor seriale con prefisso `BLE EVENT:`.
- `events` mantiene anche l'ultimo payload leggibile via read.
- `request_id` e `session_id` sono stringhe opache.

## Test senza periferiche di acquisizione

Questi test validano contratto BLE, stati ed errori. Non validano la qualita'
della calibrazione reale.

### 1. Info read stabile

Leggere `info` piu' volte senza premere `m/M` o BOOT.

Atteso:

```json
{"maintenance_enabled":false}
```

Premere `m` o `M` su seriale.

Atteso:

```text
Maintenance mode enabled
```

Rileggere `info`.

Atteso:

```json
{"maintenance_enabled":true}
```

### 2. Guardrail maintenance

Con maintenance disattiva:

```json
{"command":"cal.start","request_id":"req-no-maint","session_id":"sess-no-maint","mode":"hot","profile_set":"coffee"}
```

Atteso:

```json
{"type":"cal.error","error":"maintenance_required","retryable":true,"recover_action":"enable_maintenance"}
```

### 3. Mode non supportato

Con maintenance attiva:

```json
{"command":"cal.start","request_id":"req-bad-mode","session_id":"sess-bad-mode","mode":"bad","profile_set":"bad"}
```

Atteso:

```json
{"type":"cal.error","error":"unsupported_mode","retryable":false,"recover_action":"choose_supported_mode"}
```

### 4. Avvio hot senza sensori

Con maintenance attiva:

```json
{"command":"cal.start","request_id":"req-hot-no-sensors","session_id":"sess-hot-no-sensors","mode":"hot","profile_set":"coffee"}
```

Atteso:

- primo evento `cal.status` con `status = "collecting_baseline"`;
- eventi progressivi `cal.status`;
- finale `cal.result` fallito per profilo invalido.

```json
{"type":"cal.result","status":"failed","mode":"hot","profile_set":"coffee","committed":false,"profile_valid":false,"error":"invalid_profile","recover_action":"check_mic_signal_and_retry"}
```

### 5. Busy

Avviare una calibrazione valida e, mentre gira, inviare un secondo `cal.start`:

```json
{"command":"cal.start","request_id":"req-busy","session_id":"sess-busy","mode":"hot","profile_set":"coffee"}
```

Atteso:

```json
{"type":"cal.error","error":"busy","retryable":true,"recover_action":"wait_for_completion"}
```

La calibrazione originale deve continuare.

### 6. Cancel reale

Avviare una calibrazione, poi inviare:

```json
{"command":"cal.cancel","request_id":"req-cancel","session_id":"sess-hot-no-sensors"}
```

Atteso:

```json
{"type":"cal.status","status":"cancelled","message":"calibration_cancelled"}
```

Subito dopo inviare un nuovo `cal.start`.

Atteso: il nuovo `cal.start` parte con `calibration_started`, non ritorna
`busy`.

### 7. Invalid JSON

Inviare:

```text
{bad
```

Atteso:

```json
{"type":"cal.error","error":"invalid_json","recover_action":"send_valid_json"}
```

### 8. Cold senza sensori

Con maintenance attiva:

```json
{"command":"cal.start","request_id":"req-cold-no-sensors","session_id":"sess-cold-no-sensors","mode":"cold","profile_set":"idle"}
```

Atteso:

```json
{"type":"cal.result","status":"failed","mode":"cold","profile_set":"idle","committed":false,"profile_valid":false,"error":"invalid_profile"}
```

## Test con periferiche collegate

Da eseguire con microfono I2S e MPU6050 collegati.

### 9. Presence hardware

All'avvio seriale non deve comparire:

```text
MPU6050 not detected
```

Se compare, la parte vibrazione non e' validabile.

### 10. Hot reale

Con maintenance attiva e macchina pronta:

```json
{"command":"cal.start","request_id":"req-hot-real","session_id":"sess-hot-real","mode":"hot","profile_set":"coffee"}
```

Atteso:

```json
{"type":"cal.result","status":"completed","mode":"hot","profile_set":"coffee","committed":true,"profile_valid":true,"error":null}
```

Verificare che `metrics_summary.rms` e `metrics_summary.peak` siano maggiori di
zero.

### 11. Cold reale

Con maintenance attiva e macchina in stato idle:

```json
{"command":"cal.start","request_id":"req-cold-real","session_id":"sess-cold-real","mode":"cold","profile_set":"idle"}
```

Atteso:

```json
{"type":"cal.result","status":"completed","mode":"cold","profile_set":"idle","committed":true,"profile_valid":true,"error":null}
```

### 12. Porta aperta

Con porta aperta e maintenance attiva:

```json
{"command":"cal.start","request_id":"req-door-open","session_id":"sess-door-open","mode":"hot","profile_set":"coffee"}
```

Atteso:

```json
{"type":"cal.error","error":"door_open","recover_action":"open_door_and_retry"}
```

Nota: il nome `open_door_and_retry` e' da rivedere se la semantica corretta e'
chiudere la porta prima di riprovare.

## Criteri di uscita firmware-contract

La fase firmware-contract e' chiusa quando:

- tutti i test senza periferiche passano;
- `cal.cancel` consente un nuovo `cal.start` immediato;
- `invalid_profile` restituisce `status = "failed"` e `committed = false`;
- con periferiche collegate almeno una calibrazione hot o cold produce
  `profile_valid = true`;
- il documento `GAP_FIRMWARE.md` resta allineato allo stato reale.

## Passaggio successivo app Flutter

Dopo la chiusura dei test firmware-contract:

- aggiungere dipendenza BLE;
- implementare permessi Android/iOS;
- implementare discovery service IC01;
- implementare codec Dart per comandi/eventi JSON;
- mappare tassonomia errori;
- costruire controller calibrazione con retry/reconnect;
- salvare i risultati validi su backend quando sara' disponibile lo schema
  `calibration_sessions`.
