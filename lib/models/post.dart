// lib/models/post.dart

/// Notion の DB（タイトル / 1st check / Canva URL / Category /
/// Check ② / Check ② 担当 / ステータス / ファイル&メディア / 著者）
/// と 1 対 1 で対応するモデルクラス。
class Post {
  /// Notion ページ ID
  final String id;

  /// タイトル（Notion プロパティ名: タイトル / type: title）
  final String title;

  /// 1st check（checkbox）
  final bool firstCheck;

  /// Canva URL（url）
  final String? canvaUrl;

  /// Category（select or multi_select）
  /// multi_select の場合は最初の1つだけ使うなら `firstCategory` getter を見てもOK。
  final List<String> categories;

  /// Check ②（checkbox）
  final bool secondCheck;

  /// Check ② 担当（people）※複数選択される可能性があるのでリスト
  final List<String> secondCheckAssignees;

  /// ステータス（status / select）
  final String? status;

  /// ファイル&メディア（files）→ URL のリスト
  final List<String> fileUrls;

  /// 著者（people）
  final List<String> authors;

  /// Notion の created_time / last_edited_time を取っておきたい場合用
  final DateTime? createdTime;
  final DateTime? lastEditedTime;

  Post({
    required this.id,
    required this.title,
    required this.firstCheck,
    this.canvaUrl,
    required this.categories,
    required this.secondCheck,
    this.secondCheckAssignees = const [],
    this.status,
    this.fileUrls = const [],
    this.authors = const [],
    this.createdTime,
    this.lastEditedTime,
  });

  /// Category の先頭だけ使いたい場合の簡易 getter
  String? get firstCategory =>
      categories.isNotEmpty ? categories.first : null;

  /// 著者の先頭だけ使いたい場合の簡易 getter
  String? get firstAuthor => authors.isNotEmpty ? authors.first : null;

  /// Cloud Functions から返却される整形済み JSON を Post に変換
  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      firstCheck: json['firstCheck'] as bool? ?? false,
      secondCheck: json['secondCheck'] as bool? ?? false,
      canvaUrl: json['canvaUrl'] as String?,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String?,
      createdTime: json['createdTime'] != null
          ? DateTime.tryParse(json['createdTime'] as String)
          : null,
      lastEditedTime: json['lastEditedTime'] != null
          ? DateTime.tryParse(json['lastEditedTime'] as String)
          : null,
    );
  }

  /// Post を JSON (Map) に変換（Cloud Functions への送信用）
  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'title': title,
      'firstCheck': firstCheck,
      'secondCheck': secondCheck,
      'canvaUrl': canvaUrl,
      'categories': categories,
      'status': status,
    };
  }

  /// Notion の「ページ JSON」から Post へ変換
  factory Post.fromNotionPage(Map<String, dynamic> page) {
    final props = page['properties'] as Map<String, dynamic>;

    String _getTitle(String key) {
      final prop = props[key];
      if (prop == null) return '';
      final List<dynamic> titleList = prop['title'] ?? [];
      if (titleList.isEmpty) return '';
      return titleList.first['plain_text'] ?? '';
    }

    bool _getCheckbox(String key) {
      final prop = props[key];
      if (prop == null) return false;
      return (prop['checkbox'] as bool?) ?? false;
    }

    String? _getUrl(String key) {
      final prop = props[key];
      if (prop == null) return null;
      return prop['url'] as String?;
    }

    List<String> _getMultiSelectNames(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> ms = prop['multi_select'] ?? [];
      return ms
          .map<String>((e) => e['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    }

    String? _getStatusName(String key) {
      final prop = props[key];
      if (prop == null) return null;
      final status = prop['status'];
      if (status == null) return null;
      return status['name'] as String?;
    }

    List<String> _getFileUrls(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> files = prop['files'] ?? [];
      return files.map<String>((f) {
        // file or external のどちらかに URL が入っている
        final fileObj = f['file'] ?? f['external'];
        if (fileObj == null) return '';
        return fileObj['url'] as String? ?? '';
      }).where((url) => url.isNotEmpty).toList();
    }

    List<String> _getPeopleNames(String key) {
      final prop = props[key];
      if (prop == null) return <String>[];
      final List<dynamic> people = prop['people'] ?? [];
      return people
          .map<String>((p) => p['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    }

    DateTime? _parseDateTime(String key) {
      final v = page[key] as String?;
      if (v == null) return null;
      return DateTime.tryParse(v);
    }

    return Post(
      id: page['id'] as String,
      title: _getTitle('タイトル'),
      firstCheck: _getCheckbox('1st check'),
      canvaUrl: _getUrl('Canva URL'),
      categories: _getMultiSelectNames('Category'),
      secondCheck: _getCheckbox('Check ②'),
      secondCheckAssignees: _getPeopleNames('Check ② 担当'),
      status: _getStatusName('ステータス'),
      fileUrls: _getFileUrls('ファイル&メディア'),
      authors: _getPeopleNames('著者'),
      createdTime: _parseDateTime('created_time'), // Notion のトップレベル
      lastEditedTime: _parseDateTime('last_edited_time'),
    );
  }
}