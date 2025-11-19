📘 ARCHITETTURA_APP.md

IC-01 Operator App — Documentazione Architetturale

Ultimo aggiornamento: {{inserire data}}

🧩 1. Panoramica generale

IC-01 Operator App è un’app Flutter che supporta due ruoli principali:

👨‍🔧 Tecnico specializzato (manutenzioni straordinarie)

Visualizza ticket aperti dal cliente via QR

Prende in carico ticket

Avvia intervento

Chiude ticket

Ogni chiusura genera una visit di tipo maintenance

👨‍🏭 Operatore refill

Vede clienti assegnati

Refill macchine

Segue i flussi “oggi / domani”

Può accedere alla sezione manutenzioni (read only / assign)

🧑‍💼 Admin (non implementato nell’MVP)

Può vedere tutto

Inserimento dati

Il backend è basato interamente su Supabase (Postgres + Row Level Security).

🗃️ 2. Moduli principali
🔹 2.1 Auth (Login)

Login via email/password (Supabase Auth)

Dopo il login viene letto il ruolo dell’utente (profiles.role)

Reindirizzamento automatico:

technician → /maintenance

refill_operator → /dashboard

Ruoli consentiti:

refill_operator
technician
admin

🔹 2.2 Dashboard Refill

Schermata principale degli operatori refill.

Fonti dati: client_states (VIEW)

Mostra:

elenco “oggi”

elenco “domani”

elenco “tutti i clienti”

KPI rapidi

Ogni cliente eredita lo stato della sua macchina peggiore

Tap su cliente → ClientDetailPage

Funziona solo per:

role = refill_operator


I tecnici la vedono bloccata.

🔹 2.3 Clienti → ClientDetailPage

Fonte dati: client_machines (VIEW)

Mostra tutte le macchine del cliente selezionato

Tap su macchina → MachineDetailPage

🔹 2.4 Macchina → MachineDetailPage

Fonte dati: machine_states (VIEW + alcuni join)

Mostra:

percentuale autonomia

stato colore (green/yellow/red/black)

info cliente/sede

Bottone:

“Refill fatto” → genera riga in refills + reset percentuale

🔹 2.5 Manutenzioni straordinarie
Lista Ticket → /maintenance

Fonte dati: ticket_list (VIEW)

Mostra listato di ticket:

stato (open, assigned, in_progress, closed)

cliente, sito, macchina

descrizione

Azioni:

“Prendi in carico”

Tap su card → /maintenance/:ticketId

Dettaglio Ticket → /maintenance/:ticketId

Fonte dati: ticket_list (singolo)

Workflow stati:

open → assigned → in_progress → closed


Azioni:

assigned: “Avvia intervento”

in_progress: “Chiudi ticket”

Su chiusura:

inserisce una riga in visits (tipo = maintenance)

🛠️ 3. Supabase – Struttura dati
🔹 3.1 Tabelle principali
profiles
Campo	Tipo	Note
id	uuid	PK = auth.users.id
full_name	text	
role	text	refill_operator / technician / admin
created_at	timestamptz	
updated_at	timestamptz	
clients

Clienti finali (bar, aziende, punti vendita).

sites

Sedi fisiche del cliente.

machines

Distributori automatici.

Campi principali:

site_id

assigned_operator_id

current_fill_percent

yearly_shots

hw_serial

refills

Storico refill con:

machine_id

operator_id

previous_fill_percent

new_fill_percent

tickets

Manutenzioni straordinarie.

Campi principali:

status → open / assigned / in_progress / closed

assigned_technician_id

description

machine_id, client_id, site_id

created_at, assigned_at, closed_at

visits

Ogni intervento “sul campo”: refill o manutenzione.

Campi:

visit_type → refill / maintenance

operator_id

client_id

site_id

ticket_id (nullable)

notes

🔹 3.2 Viste
client_states

stato per ogni cliente

aggrega tutte le macchine

calcola worst_state

conta machines_to_refill

centrale per dashboard refill

client_machines

tutte le macchine del cliente

usata da ClientDetailPage

machine_states

dettaglio macchina

unisce machines + sito + cliente

calcola colore stato

ticket_list

vista completa per manutenzioni

join: tickets + machines + sites + clients

🧭 4. Navigazione (GoRouter)

Struttura:

/login

ShellRoute  (include main_shell.dart → bottom nav)
├── /dashboard
├── /clients
├── /clients/:clientId
├── /machines/:machineId
├── /maintenance
└── /maintenance/:ticketId

Funzione dei moduli:

ShellRoute → bottom navigation globale

MainShell → logica ruolo (disattiva icone per i tecnici)

/maintenance/:ticketId → dettaglio ticket

🎨 5. Bottom Navigation (MainShell)

Tre icone:

[ Oggi/Domani ]  → /dashboard
[ Tutti ]        → /clients
[ Manutenzioni ] → /maintenance

Regole ruolo:
Ruolo	Oggi/Domani	Tutti	Manutenzioni
refill_operator	✔️	✔️	✔️
technician	🚫 (grigia)	🚫 (grigia)	✔️

Tecnico:

tap su icone disattivate → snackbar: “Sezione non disponibile”.

🔄 6. Flussi (workflow)
🔹 6.1 Login

email/password → Supabase Auth

fetch ruolo → profiles.role

redirect:

technician → /maintenance

operator → /dashboard

🔹 6.2 Refill

apri macchina → MachineDetailPage

tap “Refill fatto”:

insert in refills

update macchina (current_fill_percent = 100)

refresh dashboard

🔹 6.3 Ticket manutenzione

cliente usa QR → apre web form → insert in tickets

l’app mostra ticket in /maintenance

uno dei tecnici:

open → “Prendi in carico”

assigned → “Avvia intervento”

in_progress → “Chiudi ticket”

su chiusura:

insert in visits

update tickets.status = closed

🧰 7. Modifiche future: dove toccare cosa
Aggiungere un nuovo stato ticket

Tabella: tickets.status → aggiungere nel CHECK

Vista: ticket_list

Pagina: TicketDetailPage → _statusLabel, _statusColor, _buildActions

Aggiungere un nuovo tab nella bottom nav

File: main_shell.dart (destinations + switch di navigazione)

File: router.dart (nuovo GoRoute)

Cambiare logica Oggi/Domani

File: dashboard_page.dart

Funzione: _splitTodayTomorrow

Aggiungere data alla macchina

Tabella: machines

Vista: machine_states

File: machine_detail_page.dart

Aggiungere metriche KPI

File: dashboard_page.dart

Funzione: _buildKpiRow

⚠️ 8. Note su RLS e sicurezza

Per ora RLS è semplice, ma in futuro:

tecnici devono leggere solo tickets

operatori refill solo macchine assegnate

admin tutto

Si consiglia:

POLICY su machines → assigned_operator_id = auth.uid()

POLICY su tickets → visibilità per operatori e tecnici

(Pronto quando necessario.)

💾 9. Deploy / Ambienti

Ambienti consigliati:

supabase-dev
supabase-staging
supabase-prod


Da configurare in:

<project_root>/lib/app/app.dart

oppure tramite .env con flutter_dotenv

📌 10. TODO (Backlog)

QR code ufficiale (pagina web pubblica)

Upload foto per manutenzioni

Notifiche realtime via Supabase Channels

Dashboard Admin web

KPI avanzati e storico manutenzioni

Routing ottimizzato (mappa + sequenza clienti)

Modalità offline (Hive/Drift)