import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// コンテンツ通報機能のService
/// Firestoreの`reports`コレクションに通報データを保存
class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 投稿を通報する
  /// 
  /// [postId] 通報対象の投稿ID（NotionのpageId）
  /// [reportedUserId] 通報対象ユーザーのID（NotionユーザーIDまたは空文字）
  Future<void> reportPost({
    required String postId,
    String? reportedUserId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('ログインが必要です');
    }

    // 通報をFirestoreに保存
    // 注: 重複チェックはセキュリティルールでreadsを禁止しているため行わない
    await _firestore.collection('reports').add({
      'reporterId': currentUser.uid,
      'reportedPostId': postId,
      'reportedUserId': reportedUserId ?? '',
      'reason': 'inappropriate',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
