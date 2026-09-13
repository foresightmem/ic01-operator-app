class AppEnv {
  static const supabaseUrl = String.fromEnvironment(
    'https://gydjrznapplpgvmrcymq.supabase.co',
    defaultValue: '',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'sb_publishable_l-JR7w04Ci147BmcEJO25w_uxWUJ9pt',
    defaultValue: '',
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
