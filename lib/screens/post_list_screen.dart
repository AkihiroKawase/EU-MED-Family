// lib/screens/post_list_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
      MaterialPageRoute(builder: (_) => const PostEditScreen()),
    );
    if (result == true) _reload();
  }

  void _goToDetail(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
    );
    if (result == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('投稿一覧')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Post>>(
          future: _futurePosts,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [
                  SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                ],
              );
            }

            if (snapshot.hasError) {
              return ListView(
                children: [
                  SizedBox(
                    height: 200,
                    child: Center(child: Text('エラーが発生しました: ${snapshot.error}')),
                  ),
                ],
              );
            }

            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 200, child: Center(child: Text('投稿がありません'))),
                ],
              );
            }

            return ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final post = posts[index];

                return ListTile(
                  leading: _PostThumb(imagePath: post.imagePath),
                  title: Text(post.title.isEmpty ? '(無題)' : post.title),
                  subtitle: Text(
                    post.firstCategory ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// 一覧のサムネ（imagePath が Storageパス or URL どちらでも対応）
class _PostThumb extends StatelessWidget {
  final String? imagePath;

  const _PostThumb({required this.imagePath});

  bool _looksLikeUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.trim().isEmpty) {
      return _placeholder();
    }

    final path = imagePath!.trim();

    // ① NotionにURLが入ってる場合
    if (_looksLikeUrl(path)) {
      return _networkThumb(path);
    }

    // ② NotionにStorageのパスが入ってる場合（例: "posts/xxx.jpg"）
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loading();
        }
        if (snap.hasError || !snap.hasData) {
          return _placeholder();
        }
        return _networkThumb(snap.data!);
      },
    );
  }

  Widget _networkThumb(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _loading();
        },
      ),
    );
  }

  Widget _loading() {
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 24),
      ),
    );
  }
}