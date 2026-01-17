import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ユーザーブロック機能のService
/// `users/{uid}`ドキュメントの`blocked_users`配列でブロックリストを管理
class BlockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ユーザーをブロックする
  Future<void> blockUser(String targetUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('ログインが必要です');
    }

    if (currentUser.uid == targetUserId) {
      throw Exception('自分自身をブロックすることはできません');
    }

    await _firestore.collection('users').doc(currentUser.uid).update({
      'blocked_users': FieldValue.arrayUnion([targetUserId]),
    });
  }

  /// ユーザーのブロックを解除する
  Future<void> unblockUser(String targetUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('ログインが必要です');
    }

    await _firestore.collection('users').doc(currentUser.uid).update({
      'blocked_users': FieldValue.arrayRemove([targetUserId]),
    });
  }

  /// ブロックしているユーザーのFirebase UIDリストを取得
  Future<List<String>> getBlockedUserIds() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return [];
    }

    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    final data = doc.data();
    if (data == null) return [];

    final blockedUsers = data['blocked_users'];
    if (blockedUsers is List) {
      return blockedUsers.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// ブロックしているユーザーのNotionユーザーIDリストを取得
  /// 投稿のauthorIdsはNotionユーザーIDなので、フィルタリングにはこちらを使用
  Future<List<String>> getBlockedNotionUserIds() async {
    final blockedFirebaseUids = await getBlockedUserIds();
    if (blockedFirebaseUids.isEmpty) return [];

    final notionUserIds = <String>[];
    
    // 各ブロックしたユーザーのNotionユーザーIDを取得
    for (final uid in blockedFirebaseUids) {
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final data = userDoc.data();
        if (data != null) {
          final notionUserId = data['notionUserId'] as String?;
          if (notionUserId != null && notionUserId.isNotEmpty) {
            notionUserIds.add(notionUserId);
          }
        }
      } catch (e) {
        // ユーザーが存在しない場合などはスキップ
      }
    }
    
    return notionUserIds;
  }

  /// 特定のユーザーがブロックされているかチェック
  Future<bool> isUserBlocked(String userId) async {
    final blockedUsers = await getBlockedUserIds();
    return blockedUsers.contains(userId);
  }
}
