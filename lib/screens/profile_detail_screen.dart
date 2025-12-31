import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../widgets/app_bottom_nav.dart';
import 'profile_edit_screen.dart';
import 'post_detail_screen.dart';
import '../services/notion_post_service.dart';
import '../models/post.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String userId;

  const ProfileDetailScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  int _refreshKey = 0;
  bool _isSyncingNotion = false;
  List<Map<String, dynamic>> _userPosts = [];
  bool _isLoadingPosts = false;
  String? _postsError;

  // いいねした記事リスト
  List<Post> _likedPosts = [];
  bool _isLoadingLikedPosts = false;
  String? _likedPostsError;

  // 表示件数制御用のフラグ
  bool _isUserPostsExpanded = false;
  bool _isLikedPostsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadUserPosts();
    _loadLikedPosts();
  }

  Future<void> _loadLikedPosts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLikedPosts = true;
      _likedPostsError = null;
    });

    try {
      // 1. Firestoreからいいねした記事のIDを取得
      final snapshot = await FirebaseFirestore.instance
          .collection('post_likes')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .get();

      final postIds = snapshot.docs.map((doc) => doc['postId'] as String).toList();

      if (postIds.isEmpty) {
        if (mounted) {
          setState(() {
            _likedPosts = [];
            _isLoadingLikedPosts = false;
          });
        }
        return;
      }

      // 2. NotionServiceを使って記事詳細を取得
      final service = NotionPostService();
      // 並列で取得して高速化
      final futures = postIds.map((id) => service.fetchPost(id));
      final posts = await Future.wait(futures);

      if (mounted) {
        setState(() {
          _likedPosts = posts;
          _isLoadingLikedPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading liked posts: $e');
      if (mounted) {
        setState(() {
          _likedPostsError = 'いいねした記事の読み込みに失敗しました';
          _isLoadingLikedPosts = false;
        });
      }
    }
  }

  Future<void> _loadUserPosts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPosts = true;
      _postsError = null;
    });

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final isOwnProfile = currentUserId == widget.userId;
      
      HttpsCallableResult result;
      if (isOwnProfile) {
        // 自分のプロフィールの場合
        final callable = FirebaseFunctions.instance.httpsCallable('getMyPosts');
        result = await callable.call();
      } else {
        // 他のユーザーのプロフィールの場合
        final callable = FirebaseFunctions.instance.httpsCallable('getPostsByUserId');
        result = await callable.call({'userId': widget.userId});
      }
      
      if (!mounted) return;
      
      final data = result.data as Map<String, dynamic>;
      final success = data['success'] as bool;
      
      if (success) {
        final posts = (data['posts'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _userPosts = posts;
        });
      } else {
        setState(() {
          _postsError = data['message'] as String? ?? '記事の取得に失敗しました';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postsError = 'エラーが発生しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchUserProfile() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
  }

  Future<void> _navigateToEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileEditScreen(),
      ),
    );
    setState(() {
      _refreshKey++;
    });
  }

  Future<void> _syncNotion() async {
    setState(() {
      _isSyncingNotion = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('syncNotionUser');
      final result = await callable.call();
      
      final data = result.data as Map<String, dynamic>;
      final success = data['success'] as bool;

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notionとの連携が完了しました'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _refreshKey++;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('連携に失敗しました。Notionの招待メールを確認してください'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingNotion = false;
        });
      }
    }
  }

  Widget _buildImageHeader({
    required String? profileImageUrl,
    required String? coverImageUrl,
  }) {
    return SizedBox(
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // カバー画像
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[300],
            ),
            child: coverImageUrl != null && coverImageUrl.isNotEmpty
                ? Image.network(
                    coverImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[300],
                      child: Icon(Icons.image, size: 40, color: Colors.grey[500]),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.teal.shade300,
                          Colors.teal.shade600,
                        ],
                      ),
                    ),
                  ),
          ),
          // プロフィールアイコン
          Positioned(
            left: 16,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[200],
                backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                child: (profileImageUrl == null || profileImageUrl.isEmpty)
                    ? const Icon(Icons.person, size: 50, color: Colors.grey)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotionSection({required bool isNotionLinked}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notion連携ステータス',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              Icon(
                isNotionLinked ? Icons.check_circle : Icons.warning,
                color: isNotionLinked ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8.0),
              Text(
                isNotionLinked ? '連携済み ✅' : '未連携 ⚠️',
                style: TextStyle(
                  color: isNotionLinked ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isNotionLinked || _isSyncingNotion
                  ? null
                  : _syncNotion,
              style: ElevatedButton.styleFrom(
                backgroundColor: isNotionLinked
                    ? Colors.grey[300]
                    : Colors.teal,
                foregroundColor: isNotionLinked
                    ? Colors.grey[600]
                    : Colors.white,
              ),
              child: _isSyncingNotion
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      isNotionLinked
                          ? '連携済み'
                          : 'Notionと同期する',
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPostsSection({required bool isOwnProfile}) {
    // 表示するリストを制御
    final int totalCount = _userPosts.length;
    final bool showAll = _isUserPostsExpanded || totalCount <= 3;
    final int displayCount = showAll ? totalCount : 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isOwnProfile ? '自分の投稿記事' : '投稿記事',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (!_isLoadingPosts)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadUserPosts,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12.0),
          if (_isLoadingPosts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_postsError != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _postsError!,
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else if (_userPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '投稿記事がありません',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayCount,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final post = _userPosts[index];
                final title = post['title'] as String? ?? '(無題)';
                final status = post['status'] as String?;
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    title.isEmpty ? '(無題)' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: status != null && status.isNotEmpty
                      ? Text(
                          'ステータス: $status',
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    final postId = post['id'] as String?;
                    if (postId != null) {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(postId: postId),
                        ),
                      );
                      if (result == true) {
                        _loadUserPosts();
                      }
                    }
                  },
                );
              },
            ),
            // もっと見るボタン
            if (totalCount > 3)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isUserPostsExpanded = !_isUserPostsExpanded;
                    });
                  },
                  icon: Icon(
                    _isUserPostsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                  ),
                  label: Text(_isUserPostsExpanded ? '閉じる' : 'もっと見る'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLikedPostsSection() {
    // 表示するリストを制御
    final int totalCount = _likedPosts.length;
    final bool showAll = _isLikedPostsExpanded || totalCount <= 3;
    final int displayCount = showAll ? totalCount : 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'いいねした投稿',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (!_isLoadingLikedPosts)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadLikedPosts,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12.0),
          if (_isLoadingLikedPosts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_likedPostsError != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _likedPostsError!,
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else if (_likedPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'いいねした記事はありません',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayCount,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final post = _likedPosts[index];
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    post.title.isEmpty ? '(無題)' : post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.id),
                      ),
                    );
                    _loadLikedPosts(); // 戻ってきたら更新（いいね解除などの反映のため）
                  },
                );
              },
            ),
            // もっと見るボタン
            if (totalCount > 3)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLikedPostsExpanded = !_isLikedPostsExpanded;
                    });
                  },
                  icon: Icon(
                    _isLikedPostsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                  ),
                  label: Text(_isLikedPostsExpanded ? '閉じる' : 'もっと見る'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        actions: [
          if (isOwnProfile)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _navigateToEdit,
            ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey(_refreshKey),
        future: _fetchUserProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('エラーが発生しました'),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('ユーザーが見つかりません'),
            );
          }

          final data = snapshot.data!.data()!;
          final profileImageUrl = data['profileImageUrl'] as String?;
          final coverImageUrl = data['coverImageUrl'] as String?;
          final displayName = data['displayName'] as String? ?? '名前未設定';
          final school = data['school'] as String? ?? '';
          final grade = data['grade'] as String? ?? '';
          final currentCountry = data['currentCountry'] as String? ?? '';
          final bio = data['bio'] as String? ?? '';
          final mbti = data['mbti'] as String? ?? '';
          final futureDream = data['futureDream'] as String? ?? '';
          final futureCountry = data['futureCountry'] as String? ?? '';
          final canvaUrl = data['canvaUrl'] as String? ?? '';
          final notionUserId = data['notionUserId'] as String?;
          final isNotionLinked = notionUserId != null && notionUserId.isNotEmpty;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notion風ヘッダー（カバー＋アイコン）
                _buildImageHeader(
                  profileImageUrl: profileImageUrl,
                  coverImageUrl: coverImageUrl,
                ),
                
                // 名前
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // 自己紹介
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      bio,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ),
                
                const SizedBox(height: 24),
                
                // プロパティリスト
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'プロフィール情報',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPropertyRow(
                        icon: Icons.location_on,
                        label: '現在の国',
                        value: currentCountry,
                      ),
                      _buildPropertyRow(
                        icon: Icons.school,
                        label: '大学',
                        value: school,
                      ),
                      _buildPropertyRow(
                        icon: Icons.grade,
                        label: '学年',
                        value: grade,
                      ),
                      _buildPropertyRow(
                        icon: Icons.psychology,
                        label: 'MBTI',
                        value: mbti,
                      ),
                      _buildPropertyRow(
                        icon: Icons.flight_takeoff,
                        label: '卒後行きたい国',
                        value: futureCountry,
                      ),
                      _buildPropertyRow(
                        icon: Icons.star,
                        label: '卒後の夢',
                        value: futureDream,
                      ),
                      if (canvaUrl.isNotEmpty)
                        _buildPropertyRow(
                          icon: Icons.link,
                          label: 'Canva URL',
                          value: canvaUrl,
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Notion連携セクション（自分のプロフィールの場合のみ表示）
                if (isOwnProfile)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildNotionSection(isNotionLinked: isNotionLinked),
                  ),
                
                // 投稿記事セクション
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildUserPostsSection(isOwnProfile: isOwnProfile),
                ),

                const SizedBox(height: 24),

                // いいねした投稿セクション
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildLikedPostsSection(),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}
