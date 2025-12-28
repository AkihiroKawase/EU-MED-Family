// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _reload() async {
    setState(() {
      _futurePost = _notionService.fetchPost(widget.postId);
    });
  }

  void _goToEdit(Post post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostEditScreen(post: post),
      ),
    );

    if (result == true) {
      await _reload();
      if (mounted) Navigator.of(context).pop(true); // 一覧側にも更新通知
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URLを開けませんでした')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URLの形式が不正です')),
      );
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
            return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
          }

          final post = snapshot.data!;
          final categoryText = post.categories.isNotEmpty
              ? post.categories.join(' / ')
              : '未設定';
          final authorText =
              post.authors.isNotEmpty ? post.authors.join(', ') : '未設定';
          final statusText = (post.status ?? '').isNotEmpty ? post.status! : '未設定';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---------------------------
              // 画像（ヒーロー枠）
              // ---------------------------
              _DetailImage(imagePath: post.imagePath),
              const SizedBox(height: 16),

              // ---------------------------
              // タイトル + ステータス
              // ---------------------------
              Text(
                post.title.isEmpty ? '(無題)' : post.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(label: 'Category', value: categoryText),
                  _Chip(label: 'Status', value: statusText),
                ],
              ),
              const SizedBox(height: 16),

              // ---------------------------
              // 著者
              // ---------------------------
              _SectionCard(
                title: '著者',
                child: Text(authorText),
              ),
              const SizedBox(height: 12),

              // ---------------------------
              // Canva URL
              // ---------------------------
              _SectionCard(
                title: 'Canva URL',
                child: post.canvaUrl == null || post.canvaUrl!.isEmpty
                    ? const Text('未登録')
                    : InkWell(
                        onTap: () => _openUrl(post.canvaUrl!),
                        child: Text(
                          'Canvaで開く',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),

              // ---------------------------
              // ファイル&メディア（PDFなど）
              // ---------------------------
              _SectionCard(
                title: 'ファイル&メディア',
                child: post.fileUrls.isEmpty
                    ? const Text('未登録')
                    : Column(
                        children: post.fileUrls.map((url) {
                          final name = _guessFileName(url);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.picture_as_pdf),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: const Text('タップして開く'),
                            onTap: () => _openUrl(url),
                          );
                        }).toList(),
                      ),
              ),

              const SizedBox(height: 20),

              // 編集ボタン
              ElevatedButton.icon(
                onPressed: () => _goToEdit(post),
                icon: const Icon(Icons.edit),
                label: const Text('編集する'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _guessFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final seg = uri.pathSegments;
      if (seg.isEmpty) return 'ファイル';
      final last = seg.last;
      // %E3%... を軽くデコード（完全じゃなくてもOK）
      return Uri.decodeComponent(last);
    } catch (_) {
      return 'ファイル';
    }
  }
}

/// 画像表示（imagePathがURL or Storageパス両対応）
class _DetailImage extends StatelessWidget {
  final String? imagePath;

  const _DetailImage({required this.imagePath});

  bool _looksLikeUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.trim().isEmpty) {
      return _placeholder();
    }

    final path = imagePath!.trim();

    if (_looksLikeUrl(path)) {
      return _image(context, path);
    }

    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loading();
        }
        if (snap.hasError || !snap.hasData) {
          return _placeholder();
        }
        return _image(context, snap.data!);
      },
    );
  }

  Widget _image(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _loading();
          },
        ),
      ),
    );
  }

  Widget _loading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.image, size: 40),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;

  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}