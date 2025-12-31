// lib/screens/post_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  late TextEditingController _statusController;
  
  // Categoryの選択肢
  static const List<String> _categoryOptions = [
    '国内実習',
    '海外実習',
    '大学紹介',
    'マッチング',
    'その他',
  ];
  String? _selectedCategory;

  // 1st check / Check②
  late bool _firstCheck;
  late bool _secondCheck;

  // Notion連携状態
  bool _isNotionLinked = false;
  bool _isCheckingNotionLink = true;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.post?.title ?? '');
    _canvaUrlController =
        TextEditingController(text: widget.post?.canvaUrl ?? '');
    _statusController =
        TextEditingController(text: widget.post?.status ?? '');
    
    // 既存のCategoryが選択肢にあればそれを選択、なければnull
    final existingCategory = widget.post?.categories.isNotEmpty == true 
        ? widget.post!.categories.first 
        : null;
    if (existingCategory != null && _categoryOptions.contains(existingCategory)) {
      _selectedCategory = existingCategory;
    }

    _firstCheck = widget.post?.firstCheck ?? false;
    _secondCheck = widget.post?.secondCheck ?? false;

    // Notion連携状態をチェック
    _checkNotionLinkStatus();
  }

  Future<void> _checkNotionLinkStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isNotionLinked = false;
          _isCheckingNotionLink = false;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!mounted) return;

      final notionUserId = doc.data()?['notionUserId'] as String?;
      setState(() {
        _isNotionLinked = notionUserId != null && notionUserId.isNotEmpty;
        _isCheckingNotionLink = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isNotionLinked = false;
          _isCheckingNotionLink = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _canvaUrlController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Categoryはプルダウンで選択した値を配列に
    final categories = _selectedCategory != null ? [_selectedCategory!] : <String>[];

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

  // Notion未連携時の保存試行時にメッセージを表示
  void _showNotionLinkRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('投稿するにはNotionとの連携が必要です。プロフィール画面から連携してください。'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 投稿可能かどうか（連携チェック中または連携済みでないと投稿不可）
    final canPost = !_isCheckingNotionLink && _isNotionLinked;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '投稿編集' : '新規投稿'),
        actions: [
          IconButton(
            onPressed: canPost ? _save : _showNotionLinkRequiredMessage,
            icon: Icon(
              Icons.check,
              color: canPost ? null : Colors.grey,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Notion未連携警告
              if (!_isCheckingNotionLink && !_isNotionLinked)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Notionと連携していないため投稿できません。\nプロフィール画面から連携してください。',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 連携チェック中のインジケーター
              if (_isCheckingNotionLink)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('連携状態を確認中...'),
                      ],
                    ),
                  ),
                ),

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

              // Category（プルダウン）
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('カテゴリを選択'),
                items: _categoryOptions.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'カテゴリを選択してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ステータス（テキスト入力）
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
                onPressed: canPost ? _save : _showNotionLinkRequiredMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPost ? null : Colors.grey.shade300,
                  foregroundColor: canPost ? null : Colors.grey.shade600,
                ),
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