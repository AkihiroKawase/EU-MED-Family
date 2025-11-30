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
  late TextEditingController _canvaUrlController;
  late TextEditingController _categoryController;
  late TextEditingController _statusController;

  // 1st check / Check②
  late bool _firstCheck;
  late bool _secondCheck;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.post?.title ?? '');
    _canvaUrlController =
        TextEditingController(text: widget.post?.canvaUrl ?? '');
    _categoryController = TextEditingController(
      text: widget.post?.categories.join(' ') ?? '',
    );
    _statusController =
        TextEditingController(text: widget.post?.status ?? '');

    _firstCheck = widget.post?.firstCheck ?? false;
    _secondCheck = widget.post?.secondCheck ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _canvaUrlController.dispose();
    _categoryController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // カテゴリはスペース区切りで複数入力可能にしておく
    final categories = _categoryController.text
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();

    final title = _titleController.text.trim();
    final canvaUrlText = _canvaUrlController.text.trim();
    final statusText = _statusController.text.trim();

    final post = Post(
      id: widget.post?.id ?? '', // 新規時は空文字で OK（upsert 側で create する想定）
      title: title,
      firstCheck: _firstCheck,
      canvaUrl: canvaUrlText.isEmpty ? null : canvaUrlText,
      categories: categories,
      secondCheck: _secondCheck,
      // ここはアプリ側では編集しない前提で、既存値を引き継ぐ
      secondCheckAssignees:
          widget.post?.secondCheckAssignees ?? <String>[],
      status: statusText.isEmpty ? null : statusText,
      fileUrls: widget.post?.fileUrls ?? <String>[],
      authors: widget.post?.authors ?? <String>[],
      createdTime: widget.post?.createdTime,
      lastEditedTime: widget.post?.lastEditedTime,
    );

    try {
      // NotionPostService 側の upsertPost は
      // 新しい Post モデルに合わせて実装してある前提
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
              // タイトル
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'タイトル',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'タイトルを入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Canva URL
              TextFormField(
                controller: _canvaUrlController,
                decoration: const InputDecoration(
                  labelText: 'Canva URL',
                  hintText: 'https://...',
                ),
              ),
              const SizedBox(height: 16),

              // Category（スペース区切りで複数）
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category（スペース区切りで複数可）',
                  hintText: '例: 医療 デザイン ...',
                ),
              ),
              const SizedBox(height: 16),

              // ステータス
              TextFormField(
                controller: _statusController,
                decoration: const InputDecoration(
                  labelText: 'ステータス',
                  hintText: '例: 未着手 / チェック中 / 完了',
                ),
              ),
              const SizedBox(height: 16),

              // 1st check
              SwitchListTile(
                title: const Text('1st check'),
                value: _firstCheck,
                onChanged: (v) {
                  setState(() => _firstCheck = v);
                },
              ),

              // Check ②
              SwitchListTile(
                title: const Text('Check ②'),
                value: _secondCheck,
                onChanged: (v) {
                  setState(() => _secondCheck = v);
                },
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