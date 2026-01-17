// lib/screens/post_detail_screen.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/post.dart';
import '../services/notion_post_service.dart';
import '../services/report_service.dart';
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
  final _reportService = ReportService();
  late Future<Post> _futurePost;
  
  // ログインユーザーのNotionユーザーID
  String? _currentUserNotionId;
  bool _isLoadingNotionId = true;

  // Like機能用の状態変数
  bool _isLiked = false;
  Stream<QuerySnapshot>? _likesStream;

  // コメント機能用の状態変数
  final _commentController = TextEditingController();
  bool _isSubmittingComment = false;
  Map<String, dynamic>? _currentUserData;

  Stream<QuerySnapshot>? _commentsStream;
  bool _isCommentsExpanded = false; // コメント一覧の開閉状態

  @override
  void initState() {
    super.initState();
    _futurePost = _notionService.fetchPost(widget.postId);
    _loadCurrentUserNotionId();
    _initLikeStatus();
    _initCommentStatus();
    _fetchCurrentUserInfo();
    _commentController.addListener(() {
      setState(() {}); // 文字数カウントなどの更新のため
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _initCommentStatus() {
    _commentsStream = FirebaseFirestore.instance
        .collection('post_comments')
        .where('postId', isEqualTo: widget.postId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _fetchCurrentUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() {
          _currentUserData = doc.data();
        });
      }
    } catch (e) {
      debugPrint('Error fetching user info: $e');
    }
  }

  Future<void> _submitComment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインが必要です')),
      );
      return;
    }

    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    if (text.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コメントは500文字以内で入力してください')),
      );
      return;
    }

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      // ユーザー情報の取得（キャッシュがない場合）
      String userName = 'Unknown User';
      String userIconUrl = '';
      
      if (_currentUserData != null) {
        userName = _currentUserData?['displayName'] ?? 'Unknown User';
        userIconUrl = _currentUserData?['profileImageUrl'] ?? '';
      } else {
        // フォールバック: 再取得試行
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
           userName = doc.data()?['displayName'] ?? 'Unknown User';
           userIconUrl = doc.data()?['profileImageUrl'] ?? '';
           _currentUserData = doc.data();
        }
      }

      await FirebaseFirestore.instance.collection('post_comments').add({
        'postId': widget.postId,
        'userId': user.uid,
        'userName': userName,
        'userIconUrl': userIconUrl,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _commentController.clear();
      if (mounted) {
        FocusScope.of(context).unfocus(); // キーボードを閉じる
      }
    } catch (e) {
      debugPrint('Error submitting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コメントの送信に失敗しました')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingComment = false;
        });
      }
    }
  }

  /// いいね機能の初期化
  void _initLikeStatus() {
    final user = FirebaseAuth.instance.currentUser;
    
    // いいね数の監視
    _likesStream = FirebaseFirestore.instance
        .collection('post_likes')
        .where('postId', isEqualTo: widget.postId)
        .snapshots();

    // 自分のいいね状態確認
    if (user != null) {
      FirebaseFirestore.instance
          .collection('post_likes')
          .doc('${widget.postId}_${user.uid}')
          .get()
          .then((doc) {
        if (mounted) {
          setState(() {
            _isLiked = doc.exists;
          });
        }
      });
    }
  }

  /// いいね切り替え処理
  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインが必要です')),
      );
      return;
    }

    // 体感速度向上のため、先にローカルのUIを更新
    setState(() {
      _isLiked = !_isLiked;
    });

    final docRef = FirebaseFirestore.instance
        .collection('post_likes')
        .doc('${widget.postId}_${user.uid}');

    try {
      if (_isLiked) {
        // いいね追加
        await docRef.set({
          'postId': widget.postId,
          'userId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // いいね削除
        await docRef.delete();
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
      // エラー時は元の状態に戻す
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('いいねの更新に失敗しました')),
        );
      }
    }
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

  Future<void> _openUrl(String url, {bool forceInApp = false}) async {
    try {
      final uri = Uri.parse(url);
      // フラグがtrueならアプリ内(InAppWebView)、falseなら外部アプリ(External)
      final mode = forceInApp ? LaunchMode.inAppWebView : LaunchMode.externalApplication;

      final ok = await launchUrl(
        uri,
        mode: mode,
        // Canva等はJSが必要なので有効化しておく
        webViewConfiguration: const WebViewConfiguration(enableJavaScript: true),
      );
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

  /// 通報ダイアログを表示
  Future<void> _showReportDialog(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この投稿を通報しますか？'),
        content: const Text(
          '不適切なコンテンツとして運営に報告します。\n悪質な場合は対応いたします。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('通報する'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _submitReport(post);
    }
  }

  /// 通報をFirestoreに送信
  Future<void> _submitReport(Post post) async {
    try {
      await _reportService.reportPost(
        postId: post.id,
        reportedUserId: post.authorIds.isNotEmpty ? post.authorIds.first : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通報しました。運営が確認します'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.orange,
          ),
        );
      }
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
      resizeToAvoidBottomInset: true, // キーボード表示時に入力欄を押し上げる
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

          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
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
                        // 通報メニュー
                        PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hasHeaderImage
                                  ? Colors.black.withOpacity(0.3)
                                  : Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: hasHeaderImage ? Colors.white : Colors.grey[700],
                            ),
                          ),
                          onSelected: (value) {
                            if (value == 'report') {
                              _showReportDialog(post);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.flag_outlined, color: Colors.red, size: 20),
                                  SizedBox(width: 8),
                                  Text('通報する', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
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

                            // いいねボタン
                            StreamBuilder<QuerySnapshot>(
                              stream: _likesStream,
                              builder: (context, snapshot) {
                                final likeCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                                final color = _isLiked ? Colors.red : Colors.grey;
                                final bgColor = _isLiked ? Colors.red.withOpacity(0.1) : Colors.grey[100];

                                return GestureDetector(
                                  onTap: _toggleLike,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isLiked ? Icons.favorite : Icons.favorite_border,
                                          color: color,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$likeCount',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'いいね！',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 24),


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
                              // Canva リンク
                              _buildLinkCard(
                                title: 'Canvaで開く',
                                subtitle: 'タップして表示', // 文言も「外部ブラウザ」から変更すると親切です
                                icon: Icons.design_services,
                                iconColor: Colors.purple,
                                // ここで true を渡す
                                onTap: () => _openUrl(post.canvaUrl!, forceInApp: true),
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
                            
                            // コメントセクションヘッダー
                            const Text(
                              'コメント',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    
                    // コメントリスト
                    _buildCommentList(),
                    
                    // 下部の余白（入力欄が被らないように少し多めに）
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
              ),
              
              // コメント入力欄
              _buildCommentInputArea(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _commentsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SelectableText('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
             child: Center(child: Padding(
               padding: EdgeInsets.all(20.0),
               child: CircularProgressIndicator(),
             )),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // 表示件数の制御
        final int totalCount = docs.length;
        final bool showAll = _isCommentsExpanded || totalCount <= 3;
        final int displayCount = showAll ? totalCount : 3;

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              // 「もっと見る/閉じる」ボタンの表示
              if (index == displayCount) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isCommentsExpanded = !_isCommentsExpanded;
                        });
                      },
                      icon: Icon(
                        _isCommentsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 20,
                      ),
                      label: Text(
                        _isCommentsExpanded 
                            ? '閉じる' 
                            : 'コメントをすべて表示（全$totalCount件）'
                      ),
                    ),
                  ),
                );
              }

              final data = docs[index].data() as Map<String, dynamic>;
              final userIconUrl = data['userIconUrl'] as String?;
              final userName = data['userName'] as String? ?? 'Unknown';
              final text = data['text'] as String? ?? '';
              final createdAt = data['createdAt'] as Timestamp?;
              final dateStr = createdAt != null
                  ? DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toDate())
                  : '';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: (userIconUrl != null && userIconUrl.isNotEmpty)
                          ? NetworkImage(userIconUrl)
                          : null,
                      child: (userIconUrl == null || userIconUrl.isEmpty)
                          ? const Icon(Icons.person, size: 20, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                userName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // テキストの省略表示（read moreなし、ellipsisのみ）
                          Text(
                            text,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Divider(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            // ボタンを表示する場合は +1
            childCount: displayCount + (totalCount > 3 ? 1 : 0),
          ),
        );
      },
    );
  }

  Widget _buildCommentInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end, // 入力欄が伸びた時にボタンを下揃えにするかどうか
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLines: 5,
                  minLines: 1,
                  maxLength: 500, // カウンターはTextFieldの機能で表示
                  decoration: InputDecoration(
                    hintText: 'コメントを入力...',
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Colors.teal),
                    ),
                    counterText: '', // デフォルトのカウンターを非表示にして自前で出すか、これを使うか。
                                     // 要件「入力欄の近くに 現在文字数 / 500 のカウンターを表示」
                                     // maxLengthを使うと右下に自動で出る。これで十分か、カスタムするか。
                                     // Flutter標準のcounterTextで十分要件を満たす。
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48, // minLines:1 のときの高さに合わせる調整
                child: Center(
                  child: _isSubmittingComment
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send),
                          color: _commentController.text.trim().isEmpty 
                              ? Colors.grey 
                              : Colors.teal,
                          onPressed: _commentController.text.trim().isEmpty 
                              ? null 
                              : _submitComment,
                        ),
                ),
              ),
            ],
          ),
          // 文字数カウンターを明示的に右下に出したい場合（標準機能で出るので一旦標準に任せるが、位置調整が必要ならRowの下に置く）
          Align(
             alignment: Alignment.centerRight,
             child: Padding(
               padding: const EdgeInsets.only(top: 4, right: 50), // 送信ボタンの左辺り
               child: Text(
                 '${_commentController.text.length} / 500',
                 style: TextStyle(
                   fontSize: 11,
                   color: _commentController.text.length > 500 ? Colors.red : Colors.grey,
                 ),
               ),
             ),
          ),
        ],
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

