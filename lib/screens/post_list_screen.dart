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
      MaterialPageRoute(
        builder: (_) => const PostEditScreen(),
      ),
    );

    // 新規作成・編集後にリロード
    if (result == true) {
      _reload();
    }
  }

  void _goToDetail(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id),
      ),
    );

    if (result == true) {
      _reload();
    }
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

            return ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final post = posts[index];

                final statusText = post.status ?? '';
                final categoryText = post.firstCategory ?? '';
                final authorText = post.firstAuthor ?? '';

                // 1行目用のテキスト（ステータス / カテゴリ）
                String metaLine = '';
                if (statusText.isNotEmpty) {
                  metaLine += 'ステータス: $statusText';
                }
                if (categoryText.isNotEmpty) {
                  if (metaLine.isNotEmpty) metaLine += ' / ';
                  metaLine += 'カテゴリ: $categoryText';
                }

                return ListTile(
                  title: Text(post.title.isEmpty ? '(無題)' : post.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (metaLine.isNotEmpty)
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