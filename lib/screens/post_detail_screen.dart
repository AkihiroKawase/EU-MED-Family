// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/notion_post_service.dart';
import 'post_edit_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({
    super.key,
    required this.postId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _notionService = NotionPostService();
  late Future<Post> _futurePost;

  @override
  void initState() {
    super.initState();
    _futurePost = _notionService.fetchPost(widget.postId);
  }

  void _goToEdit(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostEditScreen(post: post),
      ),
    );

    if (result == true) {
      setState(() {
        _futurePost = _notionService.fetchPost(widget.postId);
      });
      Navigator.of(context).pop(true); // 一覧側に「更新されたよ」と伝える
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿詳細'),
      ),
      body: FutureBuilder<Post>(
        future: _futurePost,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('エラーが発生しました: ${snapshot.error}'),
            );
          }

          final post = snapshot.data!;
          final tagText = post.hashtags.isNotEmpty
              ? '#${post.hashtags.join(' #')}'
              : '';

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text(
                  post.title.isEmpty ? '(無題)' : post.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                if (tagText.isNotEmpty)
                  Text(
                    tagText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'コメント',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(post.comment),
                const SizedBox(height: 16),
                const Text(
                  'PDF URL',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  post.pdfUrl.isEmpty ? '未登録' : post.pdfUrl,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _goToEdit(post),
                  icon: const Icon(Icons.edit),
                  label: const Text('編集する'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}