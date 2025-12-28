import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  // Text
  late final TextEditingController _titleController;
  late final TextEditingController _canvaUrlController;

  // Dropdown values
  String? _selectedCategory;
  String? _selectedStatus;

  // Checks
  late bool _firstCheck;
  late bool _secondCheck;

  // Image
  final _picker = ImagePicker();
  XFile? _pickedImage;
  String? _existingImagePath; // 編集時に既に保存されている Storage path
  Future<String?>? _existingImageUrlFuture;

  bool get _isEdit => widget.post != null;

  // ✅ Category 候補（固定）
  static const List<String> _categoryOptions = [
    '海外実習',
    '国試情報',
    '国内実習',
    '就職先情報',
    '大学の受験',
    '大学紹介',
    '入試情報',
  ];

  // ✅ Status 候補（Notion 側の status の選択肢と完全一致させる）
  // ここはあなたの Notion の「ステータス」候補名に合わせて編集してください
  static const List<String> _statusOptions = [
    '未着手',
    '執筆中',
    'チェック中',
    '完了',
  ];

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.post?.title ?? '');
    _canvaUrlController =
        TextEditingController(text: widget.post?.canvaUrl ?? '');

    // checks
    _firstCheck = widget.post?.firstCheck ?? false;
    _secondCheck = widget.post?.secondCheck ?? false;

    // dropdown initial values
    final categories = widget.post?.categories ?? const <String>[];
    _selectedCategory = categories.isNotEmpty ? categories.first : null;

    _selectedStatus = widget.post?.status;

    // image
    _existingImagePath = widget.post?.imagePath;
    if (_existingImagePath != null && _existingImagePath!.isNotEmpty) {
      _existingImageUrlFuture = _getDownloadUrlFromPath(_existingImagePath!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _canvaUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xfile == null) return;

    setState(() {
      _pickedImage = xfile;
    });
  }

  Future<String?> _getDownloadUrlFromPath(String path) async {
    final ref = FirebaseStorage.instance.ref(path);
    return await ref.getDownloadURL();
  }

  /// ✅ 画像をStorageにアップして「path」を返す
  /// - 新しく選んでいない場合は既存pathを使う
  /// - 画像が無いなら null
  Future<String?> _uploadImageAndGetPath() async {
    // 新しく画像を選んでいない → 既存のまま
    if (_pickedImage == null) {
      if (_existingImagePath != null && _existingImagePath!.isNotEmpty) {
        return _existingImagePath!;
      }
      return null;
    }

    final file = File(_pickedImage!.path);

    // 例: posts/{timestamp}.jpg
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final storagePath = 'posts/$fileName.jpg';

    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(file);

    return storagePath;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final canvaUrlText = _canvaUrlController.text.trim();

    // ✅ Categoryはselect想定：1つだけ送る
    final categories =
        (_selectedCategory == null) ? <String>[] : <String>[_selectedCategory!];

    // ✅ Status は候補からのみ（無選択なら null で送る）
    final status = _selectedStatus;

    try {
      // ① 画像アップ → imagePath を確定
      final imagePath = await _uploadImageAndGetPath();

      final post = Post(
        id: widget.post?.id ?? '',
        title: title,
        firstCheck: _firstCheck,
        secondCheck: _secondCheck,
        canvaUrl: canvaUrlText.isEmpty ? null : canvaUrlText,
        categories: categories,
        status: status, // null OK

        // ★ 追加：Notionに保存する
        imagePath: imagePath,

        // 編集時は引き継ぎ
        secondCheckAssignees: widget.post?.secondCheckAssignees ?? const [],
        fileUrls: widget.post?.fileUrls ?? const [],
        authors: widget.post?.authors ?? const [],
        createdTime: widget.post?.createdTime,
        lastEditedTime: widget.post?.lastEditedTime,
      );

      await _notionService.upsertPost(post, isUpdate: _isEdit);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedFile = _pickedImage;

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

              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                ),
                items: _categoryOptions
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) {
                  // 必須にしたいならここでチェック
                  // if (v == null || v.isEmpty) return 'Categoryを選択してください';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Status Dropdown
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'ステータス',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('未選択'),
                  ),
                  ..._statusOptions.map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedStatus = v),
              ),
              const SizedBox(height: 16),

              // 1st check
              SwitchListTile(
                title: const Text('1st check'),
                value: _firstCheck,
                onChanged: (v) => setState(() => _firstCheck = v),
              ),

              // Check ②
              SwitchListTile(
                title: const Text('Check ②'),
                value: _secondCheck,
                onChanged: (v) => setState(() => _secondCheck = v),
              ),

              const SizedBox(height: 16),

              // 画像選択
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text('画像を選択'),
              ),

              const SizedBox(height: 12),

              // 画像プレビュー
              if (pickedFile != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(pickedFile.path),
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                )
              else if (_existingImageUrlFuture != null)
                FutureBuilder<String?>(
                  future: _existingImageUrlFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final url = snap.data;
                    if (url == null || url.isEmpty) {
                      return const Text('画像は未登録です');
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                )
              else
                const Text('画像は未登録です'),

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