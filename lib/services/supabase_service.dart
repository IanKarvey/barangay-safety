import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Singleton wrapper around the Supabase client.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService _instance = SupabaseService._();
  static SupabaseService get instance => _instance;

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  // Quick accessors
  GoTrueClient get auth => client.auth;
  SupabaseStorageClient get storage => client.storage;

  /// Current authenticated user, or null.
  User? get currentUser => auth.currentUser;

  /// Current session, or null.
  Session? get currentSession => auth.currentSession;

  /// Whether a user is signed in.
  bool get isAuthenticated => currentUser != null;
}
