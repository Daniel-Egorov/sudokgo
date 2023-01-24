import 'package:sudokgo/src/hive/hive_wrapper.dart';
import 'package:sudokgo/src/types/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SudokGoApi {
  const SudokGoApi();

  static final supabase = Supabase.instance.client;

  static Future<void> login(String email) async {
    await supabase.auth.signInWithOtp(
      email: email,
      shouldCreateUser: true,
      emailRedirectTo: 'com.danielegorov.sudokgo://login-callback/',
    );
  }

  static Session? session() {
    return supabase.auth.currentSession;
  }

  static Future<void> logout() async {
    await supabase.auth.signOut();
  }

  /// Create the user row in the users table
  /// 
  /// perform an upsert on the users table to either create or update the current
  /// users row in the table which will ensure they have a row in the table and
  /// that the `display_name` property in the table is in sync with the display
  /// name stored in the [Hive]
  static Future<void> upsertUserRow() async {
    await supabase.from('users')
      .upsert({
        'created_at': supabase.auth.currentUser?.createdAt,
        'id': supabase.auth.currentUser?.id,
        'email': supabase.auth.currentUser?.email,
        'display_name': HiveWrapper.getDisplayName(),
      });
  }

  static Future<void> addFriend(String email) async {
    if (email == supabase.auth.currentUser?.email) {
      throw YouAreYourOwnBestFriendException('you are your own best friend :)');
    }
    
    final otherUserId = await getIdByEmail(email);
    
    if (otherUserId == null) {
      throw UserNotFoundException('this user does not exist');
    }

    final existingStatus = await getFriendshipStatus(otherUserId);

    // ignore: unrelated_type_equality_checks
    if (FriendshipStatus.blocked == existingStatus) {
      throw UserNotFoundException('this user does not exist');
    // ignore: unrelated_type_equality_checks
    } else if (FriendshipStatus.pending == existingStatus) {
      throw RelationshipAlreadyExistsException('already sent a request');
    // ignore: unrelated_type_equality_checks
    } else if (FriendshipStatus.accepted == existingStatus) {
      throw RelationshipAlreadyExistsException('already friends');
    }

    await supabase.from('friendships')
      .insert({
        'source_user_id': supabase.auth.currentUser?.id,
        'target_user_id': otherUserId,
        'status': FriendshipStatus.pending.value,
      });
  }

  /// get the [int] representation of the relationship between the current user
  /// and `other` which represents the `id` of the other user
  static Future<int> getFriendshipStatus(String other) async {
    final query = await supabase.from('friendships')
      .select<List<Map<String, dynamic>>>('status')
      .match({
        'source_user_id': supabase.auth.currentUser?.id,
        'target_user_id': other,
      });
    
    return query.isEmpty ? -1 : query[0]['status'];
  }

  /// get the [String] id of a user based on their email
  /// 
  /// returns null if no user is found
  static Future<String?> getIdByEmail(String email) async {
    final query = await supabase.from('users')
      .select<List<Map<String, dynamic>>>('id')
      .eq('email', email);
    
    return query.isEmpty ? null : query[0]['id'];
  }
}

class SudokGoException implements Exception {
  final String msg;
  SudokGoException(this.msg);

  @override
  String toString() {
    return 'SudokGoException: $msg';
  }
}

class UserNotFoundException extends SudokGoException {
  UserNotFoundException(super.msg);

  @override
  String toString() {
    return 'SudokGoException: UserNotFound: $msg';
  }
}

class RelationshipAlreadyExistsException extends SudokGoException {
  RelationshipAlreadyExistsException(super.msg);

  @override
  String toString() {
    return 'SudokGoException: RelationshipAlreadyExists: $msg';
  }
}

class YouAreYourOwnBestFriendException extends RelationshipAlreadyExistsException {
  YouAreYourOwnBestFriendException(super.msg);
}
