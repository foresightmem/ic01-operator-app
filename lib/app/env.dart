class AppEnv {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const supabaseAnonKey = supabasePublishableKey;

  static void validate() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY dart define.',
      );
    }
  }
}
