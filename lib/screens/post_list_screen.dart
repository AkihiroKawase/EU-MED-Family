// lib/screens/post_list_screen.dart
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/notion_post_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'post_detail_screen.dart';
import 'post_edit_screen.dart';

class PostListScreen extends StatefulWidget {
  const PostListScreen({super.key});

  @override
  State<PostListScreen> createState() => _PostListScreenState();
}

class _PostListScreenState extends State<PostListScreen> {
  final _notionService = NotionPostService();
  late Future<List<Post>> _futurePosts;

  String? _selectedCategory; // null = すべて

  @override
  void initState() {
    super.initState();
    _futurePosts = _notionService.fetchPosts();
  }

  Future<void> _reload() async {
    setState(() {
      _futurePosts = _notionService.fetchPosts();
    });
  }

  void _goToNewPost() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostEditScreen()),
    );

    if (result == true) {
      _reload();
    }
  }

  void _goToDetail(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
    );

    if (result == true) {
      _reload();
    }
  }

  // --- カテゴリ文字列の正規化（未設定をまとめる） ---
  String _normalizeCategory(Post p) {
    final raw = (p.categories.isNotEmpty ? p.categories.first : '').trim();
    return raw.isEmpty ? '未設定' : raw;
  }

  // --- チップ一覧（postsから自動生成） ---
  List<String> _buildCategoryOptions(List<Post> posts) {
    final set = <String>{};
    for (final p in posts) {
      set.add(_normalizeCategory(p));
    }

    final list = set.toList()..sort();
    if (list.remove('未設定')) list.add('未設定');
    return list;
  }

  // --- 選択カテゴリで絞り込み ---
  List<Post> _filterPosts(List<Post> posts) {
    if (_selectedCategory == null) return posts;
    return posts.where((p) => _normalizeCategory(p) == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('投稿一覧'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Post>>(
          future: _futurePosts,
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
                    Text(
                      'エラーが発生しました',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _reload,
                      child: const Text('再読み込み'),
                    ),
                  ],
                ),
              );
            }

            final posts = snapshot.data ?? [];

            if (posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      '投稿がありません',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '右下のボタンから新規投稿できます',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            final categories = _buildCategoryOptions(posts);
            final filteredPosts = _filterPosts(posts);

            return CustomScrollView(
              slivers: [
                // カテゴリフィルター
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildCategoryChip(
                                label: 'すべて',
                                isSelected: _selectedCategory == null,
                                onTap: () => setState(() => _selectedCategory = null),
                              ),
                              ...categories.map((c) => _buildCategoryChip(
                                    label: c,
                                    isSelected: _selectedCategory == c,
                                    onTap: () => setState(() => _selectedCategory = c),
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${filteredPosts.length}件の記事',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 投稿リスト
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = filteredPosts[index];
                        return _buildPostCard(post);
                      },
                      childCount: filteredPosts.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToNewPost,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(Post post) {
    final categoryText = _normalizeCategory(post);
    final authorText = post.firstAuthor ?? '';
    final hasImage = post.fileUrls.isNotEmpty;
    final imageUrl = hasImage ? post.fileUrls.first : null;

    return GestureDetector(
      onTap: () => _goToDetail(post),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: テキスト情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // カテゴリタグ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getCategoryColor(categoryText).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        categoryText,
                        style: TextStyle(
                          fontSize: 11,
                          color: _getCategoryColor(categoryText),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // タイトル
                    Text(
                      post.title.isEmpty ? '(無題)' : post.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // メタ情報
                    Row(
                      children: [
                        if (authorText.isNotEmpty) ...[
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              authorText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右側: サムネイル画像
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 88,
                  height: 88,
                  color: Colors.grey[200],
                  child: hasImage && imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildThumbnailPlaceholder(),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                        )
                      : _buildThumbnailPlaceholder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.article_outlined,
        size: 32,
        color: Colors.grey[400],
      ),
    );
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
}
