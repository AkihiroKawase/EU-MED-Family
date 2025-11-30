// lib/screens/post_edit_screen.dart
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/notion_post_service.dart';

class PostEditScreen extends StatefulWidget {
  final Post? post;

  const PostEditScreen({super.key, this.post});

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notionService = NotionPostService();

  late TextEditingController _titleController;
  late TextEditingController _pdfUrlController;
  late TextEditingController _commentController;
  late TextEditingController _hashtagsController;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.post?.title ?? '');
    _pdfUrlController =
        TextEditingController(text: widget.post?.pdfUrl ?? '');
    _commentController =
        TextEditingController(text: widget.post?.comment ?? '');
    _hashtagsController = TextEditingController(
      text: widget.post?.hashtags.join(' ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pdfUrlController.dispose();
    _commentController.dispose();
    _hashtagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final hashtags = _hashtagsController.text
        .split(RegExp(r'\s+'))
        .map((e) => e.replaceFirst('#', ''))
        .where((e) => e.isNotEmpty)
        .toList();

    final post = Post(
      id: widget.post?.id ?? '',
      title: _titleController.text.trim(),
      pdfUrl: _pdfUrlController.text.trim(),
      comment: _commentController.text.trim(),
      hashtags: hashtags,
    );

    try {
      await _notionService.upsertPost(post, isUpdate: _isEdit);
      if (mounted) {
        Navigator.of(context).pop(true); // 保存成功を親に伝える
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '投稿編集' : '新規投稿'),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '記事名',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '記事名を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pdfUrlController,
                decoration: const InputDecoration(
                  labelText: 'PDF URL',
                  hintText: 'https://...',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'コメント',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hashtagsController,
                decoration: const InputDecoration(
                  labelText: 'ハッシュタグ（スペース区切り, #なしでもOK）',
                  hintText: 'flutter notion pdf ...',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(_isEdit ? '更新する' : '投稿する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}