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
    // 未設定は最後に回す（好み）
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
      appBar: AppBar(
        title: const Text('投稿一覧'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Post>>(
          future: _futurePosts,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [
                  SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                children: [
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('エラーが発生しました: ${snapshot.error}'),
                    ),
                  ),
                ],
              );
            }

            final posts = snapshot.data ?? [];

            if (posts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(
                    height: 200,
                    child: Center(child: Text('投稿がありません')),
                  ),
                ],
              );
            }

            final categories = _buildCategoryOptions(posts);
            final filteredPosts = _filterPosts(posts);

            // 先頭(チップ領域) + 投稿リスト(filteredPosts)
            return ListView.separated(
              itemCount: 1 + filteredPosts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                // --- 先頭はチップ領域 ---
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('すべて'),
                              selected: _selectedCategory == null,
                              onSelected: (_) => setState(() => _selectedCategory = null),
                            ),
                            ...categories.map((c) => ChoiceChip(
                                  label: Text(c),
                                  selected: _selectedCategory == c,
                                  onSelected: (_) => setState(() => _selectedCategory = c),
                                )),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '表示: ${filteredPosts.length}件',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }

                // --- ここから投稿リスト ---
                final post = filteredPosts[index - 1];

                final statusText = post.status ?? '';
                // ★ ここが修正ポイント：表示側も正規化カテゴリを使う（消えない）
                final categoryText = _normalizeCategory(post);
                final authorText = post.firstAuthor ?? '';

                // 1行目用のテキスト（ステータス / カテゴリ）
                final metaLine = [
                  if (statusText.isNotEmpty) 'ステータス: $statusText',
                  'カテゴリ: $categoryText', // ← 常に表示（未設定も含む）
                ].join(' / ');

                return ListTile(
                  title: Text(post.title.isEmpty ? '(無題)' : post.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (authorText.isNotEmpty)
                        Text(
                          '著者: $authorText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _goToDetail(post),
                );
              },
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
}