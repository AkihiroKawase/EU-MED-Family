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

          if (!snapshot.hasData) {
            return const Center(child: Text('データが見つかりませんでした'));
          }

          final post = snapshot.data!;
          final statusText = post.status ?? '';
          final categoryText = post.firstCategory ?? '';
          final authorText = post.firstAuthor ?? '';
          final created = post.createdTime;
          final updated = post.lastEditedTime;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // タイトル
                Text(
                  post.title.isEmpty ? '(無題)' : post.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),

                // ステータス & カテゴリ
                if (statusText.isNotEmpty || categoryText.isNotEmpty)
                  Text(
                    [
                      if (statusText.isNotEmpty) 'ステータス: $statusText',
                      if (categoryText.isNotEmpty) 'カテゴリ: $categoryText',
                    ].join(' / '),
                    style: const TextStyle(fontSize: 13),
                  ),

                // 著者
                if (authorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '著者: $authorText',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],

                // 日付
                if (created != null || updated != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (created != null)
                        '作成: ${created.toLocal().toString().split(".").first}',
                      if (updated != null)
                        '更新: ${updated.toLocal().toString().split(".").first}',
                    ].join(' / '),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],

                const SizedBox(height: 24),

                // Canva URL
                const Text(
                  'Canva URL',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  (post.canvaUrl == null || post.canvaUrl!.isEmpty)
                      ? '未登録'
                      : post.canvaUrl!,
                  style: TextStyle(
                    decoration: (post.canvaUrl == null ||
                            post.canvaUrl!.isEmpty)
                        ? TextDecoration.none
                        : TextDecoration.underline,
                    color: (post.canvaUrl == null ||
                            post.canvaUrl!.isEmpty)
                        ? null
                        : Colors.blue,
                  ),
                ),

                const SizedBox(height: 24),

                // チェック状況
                const Text(
                  'チェック状況',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      post.firstCheck
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('1st check'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      post.secondCheck
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Check ②'),
                  ],
                ),

                const SizedBox(height: 24),

                // ファイル & メディア
                const Text(
                  'ファイル & メディア',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (post.fileUrls.isEmpty)
                  const Text('ファイルは登録されていません')
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < post.fileUrls.length; i++) ...[
                        Text(
                          'ファイル ${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          post.fileUrls[i],
                          style: const TextStyle(
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ]
                    ],
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