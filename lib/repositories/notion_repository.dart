import 'package:cloud_functions/cloud_functions.dart';

class NotionRepository {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Notion連携を同期する
  /// 成功時は Notion User ID を返し、失敗時は null を返す
  Future<String?> syncNotionUser() async {
    try {
      final callable = _functions.httpsCallable('syncNotionUser');
      final result = await callable.call();
      
      final data = result.data as Map<String, dynamic>;
      final success = data['success'] as bool;
      final notionUserId = data['notionUserId'] as String?;

      if (success && notionUserId != null) {
        return notionUserId;
      }
      
      return null;
    } catch (e) {
      print('Error syncing Notion user: $e');
      return null;
    }
  }
}



