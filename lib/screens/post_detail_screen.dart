// lib/screens/post_detail_screen.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/post.dart';
import '../services/notion_post_service.dart';
import 'post_edit_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

Future<void> openPdfFromNotion(String pageId) async {
  final callable =
      FirebaseFunctions.instance.httpsCallable('getMediaUrl');

  final result = await callable.call({'pageId': pageId});
  final url = result.data['url'] as String?;

  if (url == null) {
    throw Exception('PDFが見つかりません');
  }

  try {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('Error launching PDF URL: $e');
    throw Exception('URLを開けませんでした');
  }
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _notionService = NotionPostService();
  late Future<Post> _futurePost;
  
  // ログインユーザーのNotionユーザーID
  String? _currentUserNotionId;
  bool _isLoadingNotionId = true;

  @override
  void initState() {
    super.initState();
    _futurePost = _notionService.fetchPost(widget.postId);
    _loadCurrentUserNotionId();
  }

  /// ログインユーザーのNotionユーザーIDをFirestoreから取得
  Future<void> _loadCurrentUserNotionId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoadingNotionId = false;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!mounted) return;

      final notionUserId = doc.data()?['notionUserId'] as String?;
      setState(() {
        _currentUserNotionId = notionUserId;
        _isLoadingNotionId = false;
      });
    } catch (e) {
      debugPrint('Error loading notionUserId: $e');
      if (mounted) {
        setState(() {
          _isLoadingNotionId = false;
        });
      }
    }
  }

  /// 現在のユーザーが投稿の著者かどうかを判定
  bool _canEditPost(Post post) {
    // NotionユーザーIDの読み込み中は編集不可
    if (_isLoadingNotionId) return false;
    
    // NotionユーザーIDがない場合は編集不可
    if (_currentUserNotionId == null || _currentUserNotionId!.isEmpty) {
      return false;
    }
    
    // 投稿の著者IDリストにログインユーザーのNotionユーザーIDが含まれているか確認
    return post.authorIds.contains(_currentUserNotionId);
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リンクを開けませんでした')),
        );
      }
    } catch (e) {
      debugPrint('Error opening URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URLの形式が不正です')),
        );
      }
    }
  }

  String _fileNameFromUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.pathSegments.isEmpty) {
        final lastSlash = url.lastIndexOf('/');
        if (lastSlash != -1 && lastSlash < url.length - 1) {
          var fileName = url.substring(lastSlash + 1);
          final queryIndex = fileName.indexOf('?');
          if (queryIndex != -1) {
            fileName = fileName.substring(0, queryIndex);
          }
          try {
            return Uri.decodeComponent(fileName);
          } catch (_) {
            return fileName.isNotEmpty ? fileName : 'ファイル';
          }
        }
        return 'ファイル';
      }
      
      final last = uri.pathSegments.last;
      try {
        final decoded = Uri.decodeComponent(last);
        return decoded.trim().isEmpty ? 'ファイル' : decoded;
      } catch (_) {
        return last.isNotEmpty ? last : 'ファイル';
      }
    } catch (e) {
      debugPrint('Error parsing URL: $e');
      return 'ファイル';
    }
  }

  void _goToEdit(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostEditScreen(post: post)),
    );

    if (result == true) {
      setState(() {
        _futurePost = _notionService.fetchPost(widget.postId);
      });
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy年MM月dd日').format(date);
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case '国内実習':
        return Colors.blue;
      case '海外実習':
        return Colors.green;
      case '大学紹介':
        return Colors.purple;
      case 'マッチング':
        return Colors.orange;
      case 'その他':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Post>(
        future: _futurePost,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('エラー: ${snapshot.error}'),
                ],
              ),
            );
          }

          final post = snapshot.data!;
          final hasHeaderImage = post.fileUrls.isNotEmpty;
          final headerImageUrl = hasHeaderImage ? post.fileUrls.first : null;
          final categoryText = post.categories.isNotEmpty 
              ? post.categories.first 
              : '未設定';

          return CustomScrollView(
            slivers: [
              // ヘッダー画像付きAppBar
              SliverAppBar(
                expandedHeight: hasHeaderImage ? 250 : 0,
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: hasHeaderImage ? Colors.white : null,
                flexibleSpace: hasHeaderImage
                    ? FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              headerImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 64,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ),
                            // グラデーションオーバーレイ
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.3),
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.5),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
                actions: [
                  if (_canEditPost(post))
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasHeaderImage
                              ? Colors.black.withOpacity(0.3)
                              : Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 20,
                          color: hasHeaderImage ? Colors.white : Colors.grey[700],
                        ),
                      ),
                      onPressed: () => _goToEdit(post),
                    ),
                ],
              ),

              // コンテンツ
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // カテゴリ & ステータス
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getCategoryColor(categoryText).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              categoryText,
                              style: TextStyle(
                                fontSize: 13,
                                color: _getCategoryColor(categoryText),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (post.status != null && post.status!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                post.status!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // タイトル
                      Text(
                        post.title.isEmpty ? '(無題)' : post.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // メタ情報（著者・日付）
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // 著者
                            if (post.authors.isNotEmpty)
                              _buildMetaRow(
                                icon: Icons.person_outline,
                                label: '著者',
                                value: post.authors.join(', '),
                              ),
                            // 投稿日
                            if (post.createdTime != null) ...[
                              if (post.authors.isNotEmpty)
                                const Divider(height: 24),
                              _buildMetaRow(
                                icon: Icons.calendar_today_outlined,
                                label: '投稿日',
                                value: _formatDate(post.createdTime),
                              ),
                            ],
                            // 更新日
                            if (post.lastEditedTime != null) ...[
                              const Divider(height: 24),
                              _buildMetaRow(
                                icon: Icons.update,
                                label: '更新日',
                                value: _formatDate(post.lastEditedTime),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // チェック状況
                      if (post.firstCheck || post.secondCheck) ...[
                        _buildSectionTitle('チェック状況'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildCheckBadge(
                              label: '1st Check',
                              isChecked: post.firstCheck,
                            ),
                            const SizedBox(width: 12),
                            _buildCheckBadge(
                              label: 'Check ②',
                              isChecked: post.secondCheck,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ファイル&メディア（ヘッダー以外のファイル）
                      if (post.fileUrls.length > 1) ...[
                        _buildSectionTitle('添付ファイル'),
                        const SizedBox(height: 12),
                        ...post.fileUrls.skip(1).map((u) {
                          final name = _fileNameFromUrl(u);
                          final isPdf = name.toLowerCase().endsWith('.pdf');
                          return _buildFileCard(
                            name: name,
                            icon: isPdf ? Icons.picture_as_pdf : Icons.attach_file,
                            iconColor: isPdf ? Colors.red : Colors.blue,
                            onTap: () => _openUrl(u),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],

                      // Canva リンク
                      if (post.canvaUrl != null && post.canvaUrl!.isNotEmpty) ...[
                        _buildSectionTitle('Canva デザイン'),
                        const SizedBox(height: 12),
                        _buildLinkCard(
                          title: 'Canvaで開く',
                          subtitle: 'タップして外部ブラウザで表示',
                          icon: Icons.design_services,
                          iconColor: Colors.purple,
                          onTap: () => _openUrl(post.canvaUrl!),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Check② 担当者
                      if (post.secondCheckAssignees.isNotEmpty) ...[
                        _buildSectionTitle('Check② 担当'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: post.secondCheckAssignees
                              .map((name) => Chip(
                                    avatar: CircleAvatar(
                                      backgroundColor: Colors.teal[100],
                                      child: Text(
                                        name.isNotEmpty ? name[0] : '?',
                                        style: TextStyle(
                                          color: Colors.teal[700],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    label: Text(name),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 編集ボタン（著者のみ表示）
                      if (_canEditPost(post))
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _goToEdit(post),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.edit),
                            label: const Text('編集する'),
                          ),
                        ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckBadge({
    required String label,
    required bool isChecked,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isChecked ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isChecked ? Colors.green[200]! : Colors.grey[300]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: isChecked ? Colors.green : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isChecked ? Colors.green[700] : Colors.grey[600],
              fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard({
    required String name,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'タップして開く',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              iconColor.withOpacity(0.1),
              iconColor.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}
