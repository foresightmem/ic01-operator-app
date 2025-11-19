IC-01 Operator App – Documentazione Supabase (DB + API)

Ultimo aggiornamento: {{09/11/2025}}

1. Panoramica
L’app IC-01 utilizza Supabase come backend:

Auth → gestione utenti (operatori refill, tecnici, admin)

Postgres → tabelle dati operative (macchine, clienti, ticket, visite, ecc.)

View → aggregazioni ottimizzate per la UI

RLS → (Row Level Security) per limitare cosa può vedere un utente (in progress / MVP semplice)

Tutto l’accesso ai dati lato Flutter avviene tramite:

final supabase = Supabase.instance.client;

// Esempio:
final data = await supabase
  .from('client_states')
  .select()
  .order('name');

2. Auth e Profili
2.1 Auth (Supabase Auth – tabella auth.users interna)

Usata per:

login via email + password

gestione sessione

identificazione utente (user.id = uuid)

L’app NON scrive direttamente in auth.users via SQL, ma usa le API Auth di Supabase.

In Flutter:

final response = await supabase.auth.signInWithPassword(
  email: email,
  password: password,
);

final user = response.user; // contiene user.id, email, ecc.

2.2 Tabella public.profiles

Scopo: estendere auth.users con info app-specifiche, in particolare il role.

Colonne principali:

Campo	Tipo	Note
id	uuid	PK, uguale a auth.users.id
full_name	text	Nome operatore/tecnico
role	text	refill_operator, technician, admin
created_at	timestamptz	default now()
updated_at	timestamptz	default now()

Ruoli attuali:

refill_operator → operatore rifornimenti

technician → tecnico manutenzioni straordinarie

admin → uso futuro

Esempio: leggere il ruolo dell’utente loggato

final user = supabase.auth.currentUser;
final profileList = await supabase
    .from('profiles')
    .select('role, full_name')
    .eq('id', user!.id)
    .limit(1);

if (profileList.isNotEmpty) {
  final role = profileList.first['role'] as String;
}

3. Tabelle principali (domain model)
3.1 clients

Scopo: azienda/cliente finale (es. bar, uffici, stabilimenti).

Colonne tipiche (semplificate):

Campo	Tipo	Note
id	uuid	PK
name	text	Nome cliente
vat	text?	P.IVA (facoltativo)
created_at	timestamptz	

Uso in app:

Lista clienti in dashboard → via view client_states

Info cliente in ticket_list

3.2 sites

Scopo: punti fisici di un cliente.

Campo	Tipo	Note
id	uuid	PK
client_id	uuid	FK → clients.id
name	text	Es. “Sede Roma”, “Piano 2”
address	text	Indirizzo completo
city	text	Città
created_at	timestamptz	

Uso in app:

Visualizzato nelle viste:

client_machines (elenco macchine per cliente)

machine_states (macchina singola)

ticket_list (ticket manutenzione: site_name, site_address, site_city)

3.3 machines

Scopo: distributore automatico.

Colonne chiave (minimo necessario per l’app):

Campo	Tipo	Note
id	uuid	PK
site_id	uuid	FK → sites.id
code	text	Codice identificativo visibile in app
assigned_operator_id	uuid?	FK → profiles.id (refill operator)
current_fill_percent	numeric	% autonomia residua
yearly_shots	integer	Numero battute erogate YTD
created_at	timestamptz	

Uso in app:

Dashboard (via client_states → aggregato per cliente)

ClientDetailPage (via view client_machines)

MachineDetailPage (via view machine_states)

Ticket (via tickets.machine_id e view ticket_list)

3.4 refills

Scopo: storico dei refill eseguiti.

Campo	Tipo	Note
id	uuid	PK
machine_id	uuid	FK → machines.id
operator_id	uuid	FK → profiles.id
previous_fill_percent	numeric	% prima del refill
new_fill_percent	numeric	% dopo il refill (tipicamente 100)
created_at	timestamptz	

Uso in app:

Creato da MachineDetailPage quando operatore preme “Refill fatto”.

Utile per KPI storici (in futuro).

Esempio inserimento (concetto):

await supabase.from('refills').insert({
  'machine_id': machineId,
  'operator_id': userId,
  'previous_fill_percent': currentPercent,
  'new_fill_percent': 100,
});

3.5 tickets

Scopo: chiamate di manutenzione straordinaria.

Colonne principali:

Campo	Tipo	Note
id	uuid	PK
machine_id	uuid	FK → machines.id
client_id	uuid	FK → clients.id
site_id	uuid	FK → sites.id
status	text	open/assigned/in_progress/closed
description	text?	Testo libero dal cliente/operatore
assigned_technician_id	uuid?	FK → profiles.id (technician)
created_at	timestamptz	default now()
assigned_at	timestamptz?	
closed_at	timestamptz?	

Workflow stato:

open → assigned → in_progress → closed


Uso in app:

Lista → ticket_list view

Dettaglio → ticket_list + update su tickets

Azioni:

“Prendo in carico” → set assigned_technician_id, status = 'assigned'

“Avvia intervento” → status = 'in_progress'

“Chiudi ticket” → status = 'closed' + create visit

3.6 visits

Scopo: log di ogni intervento sul campo (refill o manutenzione).

Campo	Tipo	Note
id	uuid	PK
operator_id	uuid	FK → profiles.id
client_id	uuid	FK → clients.id
site_id	uuid	FK → sites.id
ticket_id	uuid?	FK → tickets.id (solo se maintenance)
visit_type	text	refill / maintenance
notes	text?	Note extra
created_at	timestamptz	default now()

Uso in app:

Creato automaticamente alla chiusura di un ticket di manutenzione (visit_type = 'maintenance').

In futuro, potrebbe essere creato anche per i refill.

4. View (READ ONLY per la UI)

Le view aggregano le tabelle in formati adatti ai widget Flutter.

4.1 client_states

Scopo: stato sintetico per cliente (per dashboard).

Colonne:

Campo	Tipo	Note
client_id	uuid	PK logico per la view
name	text	Nome cliente
worst_state	text	Stato più critico tra le macchine
total_machines	int	Numero macchine del cliente
machines_to_refill	int	Quante sono sotto soglia (“da refillare”)

Mappato in Flutter da ClientState.fromMap

class ClientState {
  final String clientId;
  final String name;
  final String worstState;
  final int totalMachines;
  final int machinesToRefill;
  ...
}


Usata da:

DashboardPage → lista clienti + KPI

Esempio query:

final data = await supabase
  .from('client_states')
  .select()
  .order('name', ascending: true);

4.2 client_machines

Scopo: elenco macchine per un dato cliente.

Colonne tipiche:

Campo	Tipo	Note
machine_id	uuid	PK logico macchina
client_id	uuid	
client_name	text	
site_id	uuid	
site_name	text	
code	text	Codice macchina
state	text	green / yellow / red / black
current_fill_percent	numeric	% autonomia

Usata da:

ClientDetailPage → per mostrare la lista di distributori del cliente e il loro stato.

4.3 machine_states

Scopo: dettaglio macchina per MachineDetailPage.

Colonne tipiche:

Campo	Tipo	Note
machine_id	uuid	
code	text	Codice macchina
client_id	uuid	
client_name	text	
site_id	uuid	
site_name	text	
current_fill_percent	numeric	
state	text	green / yellow / red / black

Usata da:

MachineDetailPage per:

mostrare stato

capire cosa aggiornare al refill

4.4 ticket_list

Scopo: vista completa dei ticket per la UI (lista + dettaglio).

Colonne (quelle usate in app):

Campo	Tipo	Note
ticket_id	uuid	PK logico del ticket
status	text	open / assigned / in_progress / closed
description	text	
created_at	timestamptz	
assigned_technician_id	uuid?	
assigned_at	timestamptz?	
closed_at	timestamptz?	
machine_id	uuid	
machine_code	text	
client_id	uuid	
client_name	text	
site_id	uuid	
site_name	text	
site_address	text	
site_city	text	

Usata da:

MaintenanceTicketsPage (lista):

select su ticket_list (status in open/assigned)

TicketDetailPage:

select su ticket_list con eq('ticket_id', ...)

5. Pattern di accesso da Flutter (Supabase client)
5.1 Select semplice
final data = await supabase
  .from('client_states')
  .select()
  .order('name', ascending: true);

5.2 Filtri multipli + order
final data = await supabase
  .from('ticket_list')
  .select()
  .inFilter('status', ['open', 'assigned'])
  .order('created_at', ascending: true);

5.3 Insert
await supabase.from('tickets').insert({
  'machine_id': machineId,
  'client_id': clientId,
  'site_id': siteId,
  'status': 'open',
  'description': 'Il cliente segnala ...',
});

5.4 Update con filtro
await supabase.from('tickets').update({
  'status': 'assigned',
  'assigned_technician_id': userId,
  'assigned_at': DateTime.now().toIso8601String(),
}).eq('id', ticketId);

6. RLS (Row Level Security) – Nota rapida

Per l’MVP le policy possono essere semplici, ma in prospettiva:

profiles: l’utente vede solo il proprio profilo

machines: l’operatore vede solo macchine assegnate (assigned_operator_id = auth.uid())

tickets:

tecnici → vedono/gestiscono tutti i ticket (per ora)

in futuro → filtri per area / team

visits, refills: visibili all’admin + (eventualmente) all’operatore/tecnico che le ha create

7. Checklist per modifiche DB

Quando cambi qualcosa in Supabase:

Aggiungi/Modifica colonna

aggiorna anche la view relativa (es. client_states, ticket_list)

Controlla i model Dart

esempi: ClientState, TicketItem, oggetti in machine_detail_page.dart

Controlla i campi nelle select()

assicurati che in Flutter vengano richieste le colonne che esistono davvero

Aggiorna questa documentazione

tabelle

viste

eventuali nuovi ruoli o flussi