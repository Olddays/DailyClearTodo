/// Compile-time config, supplied via --dart-define at build/run time, e.g.:
///   flutter run -d linux \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Only the anon key is embedded in the client -- it's safe to ship since every
/// table is protected by Row Level Security. The service-role key never leaves
/// the Edge Function.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
