// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/post.dart';
import '../services/notion_post_service.dart';
import 'post_edit_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リンクを開けませんでした')),
      );
    }
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file';
    final decoded = Uri.decodeComponent(last);
    return decoded.trim().isEmpty ? 'ファイル' : decoded;
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

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('投稿詳細')),
      body: FutureBuilder<Post>(
        future: _futurePost,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }

          final post = snapshot.data!;

          // まずここで値が入っているか確認（デバッグ用）
          debugPrint('DETAIL post: '
              'cats=${post.categories}, authors=${post.authors}, '
              'files=${post.fileUrls}, status=${post.status}, canva=${post.canvaUrl}');

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // タイトル
                Text(
                  post.title.isEmpty ? '(無題)' : post.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

                // ステータス（あれば）
                if ((post.status ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text(post.status!),
                        ),
                      ],
                    ),
                  ),

                // カテゴリー
                _sectionTitle('カテゴリー'),
                if (post.categories.isEmpty)
                  const Text('未設定')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: post.categories
                        .map((c) => Chip(label: Text(c)))
                        .toList(),
                  ),

                // 著者
                _sectionTitle('著者'),
                if (post.authors.isEmpty)
                  const Text('未設定')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        post.authors.map((a) => Chip(label: Text(a))).toList(),
                  ),

                // ファイル&メディア（PDFなど）
                _sectionTitle('ファイル&メディア'),
                if (post.fileUrls.isEmpty)
                  const Text('未設定')
                else
                  Column(
                    children: post.fileUrls.map((u) {
                      final name = _fileNameFromUrl(u);
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf),
                          title: Text(name),
                          subtitle: const Text('タップして開く'),
                          onTap: () => _openUrl(u), // まずは外部でOK
                        ),
                      );
                    }).toList(),
                  ),

                // Canva URL
                _sectionTitle('Canva'),
                if ((post.canvaUrl ?? '').isEmpty)
                  const Text('未設定')
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.design_services),
                      title: const Text('Canvaで開く'),
                      subtitle: const Text('タップして外部ブラウザで開く'),
                      onTap: () => _openUrl(post.canvaUrl!),
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