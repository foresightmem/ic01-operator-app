class AppEnv {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gydjrznapplpgvmrcymq.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_l-JR7w04Ci147BmcEJO25w_uxWUJ9pt',
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
