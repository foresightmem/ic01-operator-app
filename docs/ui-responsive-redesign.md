# UI responsive redesign audit

Data audit: 2026-08-06

Ambito: applicazione Flutter `ic01-operator-app`. Il firmware in
`ic-01-firwmare` non viene modificato. L'audit e gli interventi sono UI-only:
non cambiano backend Supabase, RPC, RLS, modello dati, ruoli o flussi
funzionali.

## Sintesi tecnica

- Tema attuale: `ThemeData.light()` con `ColorScheme.fromSeed`, Material 3
  implicito, palette blu IC-01 (`0xFF0052CC`, `0xFF1B73E8`), background grigio
  chiaro e card con radius 12/16/18 sparsi.
- Identita': la UI esistente comunica "MVP/consumer generic" piu' che prodotto
  industriale B2B. Mancano token MAGMA condivisi per nero, bianco, petrolio e
  arancione.
- Responsiveness: alcuni layout usano `LayoutBuilder`, ma i breakpoint sono
  locali. Non c'e' un sistema centrale per compact/tablet/desktop.
- Tipografia: molti `TextStyle(fontSize: ...)` locali, gerarchia non uniforme e
  testi secondari spesso grigi a basso contrasto.
- Spacing/radius/elevation: padding 8/12/14/16/20/24 e radius 10/12/16/18/999
  distribuiti per schermata. Elevation variabile e card troppo morbide per
  l'identita' richiesta.
- Componenti condivisi: assenti per page padding, content width, card, KPI,
  status pill, empty/error/loading state, dialog responsivi.
- Navigazione: operatore in `MainShell` con bottom navigation; admin fuori shell
  con singoli `Scaffold` e AppBar. L'email in AppBar crea pressione orizzontale
  su mobile.
- Test: presenti test unit/widget per onboarding validation e public support.
  Non risultano golden test.

## Inventario schermate e flussi

| Schermata / flusso | Route | Ruolo | Target | Note audit |
| --- | --- | --- | --- | --- |
| Login | `/login` | condivisa | adattiva | Card centrale max 420; brand IC-01/GEDA non allineato a MAGMA; testi piccoli, errore non incorniciato. |
| Reset password | `/reset-password` | condivisa | adattiva | Layout simile login ma meno brandizzato; necessita max width e stati coerenti. |
| Segnalazione pubblica | `/segnalazione`, `/support` | condivisa/pubblica | mobile-first | Form usabile, ma card consumer-like; scelta motivo custom senza token condivisi; success state da riallineare. |
| Dashboard operatore | `/dashboard` | operatore | mobile-first | KPI in `Row` fissa a tre colonne; email in AppBar; empty/loading/error minimali; lista clienti leggibile ma card e stati non coerenti. |
| Tutti i clienti operatore | `/clients` | operatore | mobile-first | Condivide `DashboardPage`; lista lunga ok, ma gerarchia e stati sono poveri. |
| Dettaglio cliente operatore | `/clients/:clientId` | operatore | mobile-first | Lista macchine semplice; empty state scarno; delete dialog standard non ottimizzato mobile. |
| Dettaglio macchina | `/machines/:machineId` | operatore | mobile-first/adattiva | Grid consumabili usa breakpoint locali; card con aspect ratio fragile; info row fissa `width: 120`. |
| Lista manutenzioni | `/maintenance` | tecnico/admin | adattiva | Card ricche ma footer in `Row` rischia overflow; filtri admin a larghezza fissa 220; email in AppBar. |
| Dettaglio ticket | `/maintenance/:ticketId` | tecnico/admin | adattiva | Informazioni non raggruppate in sezioni; azioni e meta non hanno gerarchia; admin read/edit state poco distinto visivamente. |
| Dashboard admin | `/admin` | admin | desktop-first/tablet | KPI e grafici presenti; breakpoint locali; contenuto molto lungo in colonna unica; card radius/elevation incoerenti. |
| Elenco clienti admin | `/admin/clients` | admin | desktop-first/tablet | Filtri in `Row` rigida; gruppi `ExpansionTile`; lista ancora phone-first su desktop largo. |
| Dettaglio cliente admin | `/admin/clients/:clientId` | admin | desktop-first/tablet | KPI in `Row`; sedi e macchine in lista unica; poca separazione tra overview e inventario. |
| Copertura assenze | `/admin/coverage` | admin | desktop/tablet | Form max 700; date in `Row` possono comprimersi; nota testuale piccola. |
| Piano copertura | `/admin/coverage/:id` | admin | desktop/tablet | Trailing dropdown `width: 260` in `ListTile`; su mobile/tablet stretto rischia overflow. |
| Configurazione macchina | `/admin/machine-config` | admin | desktop/tablet | Form operativa ma narrow; save bar in `Row`; editor tile con aspect ratio locale. |
| Attivita' recenti | `/admin/activities` | admin | adattiva | Lista semplice senza empty/error state ricco; AppBar standalone. |
| Creazione cliente | dialog | operatore/admin | adattiva | `AlertDialog` con `SizedBox(width: 420)`; content scroll solo parziale; azioni standard. |
| Creazione sede | dialog | operatore/admin | adattiva | `AlertDialog` con `SizedBox(width: 420)`; `Column` non sempre scrollabile; autocomplete indirizzo puo' allungare. |
| Creazione macchina | dialog | operatore/admin | adattiva | `AlertDialog` con `SizedBox(width: 520)`; form lungo, dropdown e loading state da rendere mobile-safe. |
| Conferme eliminazione | dialog | operatore/admin | adattiva | Dialog standard senza constraint centralizzati; pulsante distruttivo da evidenziare in modo coerente. |
| Empty/loading/error | varie | tutti | adattiva | Stati presenti ma spesso solo `Text` o spinner; manca componente coerente e spazio leggibile. |

## Problemi principali

- Overflow potenziali: KPI operatore in tre colonne; filtri admin e ticket con
  dropdown fissi; `ListTile.trailing` largo nel piano copertura; AppBar con email
  visibile su mobile; bottoni affiancati in save bar e date picker.
- Contenuto tagliato/scorrimento errato: dialog onboarding con larghezze fisse;
  form lunghi non sempre hanno altezza massima; grafici con label lunghe solo
  parzialmente mitigati da scroll orizzontale.
- Gerarchia visiva: dashboard ticket e dettaglio ticket non distinguono bene
  header, stato, meta, contenuto e azioni; dashboard admin e operatori usano KPI
  simili a card generiche.
- Coerenza: radius, padding, colori stato e typography sono duplicati.
- Accessibilita': contrasto dei grigi secondari da alzare; touch target e
  pulsanti su mobile da stabilizzare; uso arancione da limitare a warning/azioni
  importanti.

## Linea di intervento

- Introdurre un design system centralizzato con token MAGMA, breakpoint, spacing,
  radius, contenitori adattivi, card operative, status pill, empty/error/loading
  state e grid responsive.
- Aggiornare il tema globale con Material 3 esplicito, palette petrolio/arancione,
  contrasto piu' alto, radius massimo 8 per card/tool surface e input compatti ma
  leggibili.
- Applicare i componenti condivisi alle schermate raggiungibili da operatore e
  admin, preservando query, redirect, permessi, RPC e callback esistenti.
- Rendere dialog e form utilizzabili su mobile tramite constraints responsive,
  altezza massima e scroll controllato.
