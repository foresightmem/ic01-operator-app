// lib/app/env.dart
// Config per IC-01 (dev). Non committare in un repo pubblico.

// ⚠️ ATTENZIONE: non committare questo file in un repo pubblico.

/// Contiene le variabili di configurazione dell'ambiente applicativo.
///
/// Per ambienti diversi (dev, staging, prod) puoi creare
/// più implementazioni o usare flavor diversi.

class AppEnv {
  // Incollato qui il Project URL di Supabase (es: https://abcd.supabase.co)
  static const supabaseUrl = 'https://atpfgkhechvdijqnflnc.supabase.co';

  // Incollato qui la anon public key di Supabase
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF0cGZna2hlY2h2ZGlqcW5mbG5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMyODE4NDUsImV4cCI6MjA3ODg1Nzg0NX0.es3apqXqK_kB2-22e0fMaNeVnMgHL_pdO4MmCAnzD0A';
}
