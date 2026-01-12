// lib/screens/post_edit_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
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
  final _imagePicker = ImagePicker();

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

  // Notion連携状態
  bool _isNotionLinked = false;
  bool _isCheckingNotionLink = true;

  // 保存中フラグ（連打防止）
  bool _isSaving = false;

  // 画像関連
  File? _selectedImage;
  String? _existingImageUrl;
  bool _imageChanged = false;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.post?.title ?? '');
    _canvaUrlController =
        TextEditingController(text: widget.post?.canvaUrl ?? '');
    _statusController =
        TextEditingController(text: widget.post?.status ?? 'チェック待ち');
    
    // 既存のCategoryが選択肢にあればそれを選択、なければnull
    final existingCategory = widget.post?.categories.isNotEmpty == true 
        ? widget.post!.categories.first 
        : null;
    if (existingCategory != null && _categoryOptions.contains(existingCategory)) {
      _selectedCategory = existingCategory;
    }

    // 既存の画像URLを取得（1枚目のみ）
    if (widget.post?.fileUrls.isNotEmpty == true) {
      _existingImageUrl = widget.post!.fileUrls.first;
    }

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

  Future<void> _pickImage() async {
    try {
      // 通信量節約のため、画像を圧縮・リサイズ
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 60, // 50〜70程度で圧縮
      );
      
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _imageChanged = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像の選択に失敗しました: $e')),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _existingImageUrl = null;
      _imageChanged = true;
    });
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final uuid = const Uuid().v4();
      final extension = file.path.split('.').last;
      final fileName = 'image_$uuid.$extension';
      final path = 'posts/$uuid/$fileName';

      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = await ref.putFile(file);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Image upload error: $e');
      return null;
    }
  }

  Future<void> _save() async {
    // 保存中の場合は何もしない（連打防止）
    if (_isSaving) return;
    
    if (!_formKey.currentState!.validate()) return;

    // 保存開始
    setState(() {
      _isSaving = true;
    });

    try {
      // 画像のアップロード処理
      List<String>? newFileUrls;
      
      if (_imageChanged) {
        if (_selectedImage != null) {
          // 新しい画像をアップロード
          final uploadedUrl = await _uploadImage(_selectedImage!);
          if (uploadedUrl != null) {
            newFileUrls = [uploadedUrl];
          } else {
            throw Exception('画像のアップロードに失敗しました');
          }
        } else {
          // 画像が削除された場合は空の配列
          newFileUrls = [];
        }
      }

      // Categoryはプルダウンで選択した値を配列に
      final categories = _selectedCategory != null ? [_selectedCategory!] : <String>[];

      final title = _titleController.text.trim();
      final canvaUrlText = _canvaUrlController.text.trim();
      final statusText = _statusController.text.trim();

      final post = Post(
        id: widget.post?.id ?? '',
        title: title,
        firstCheck: widget.post?.firstCheck ?? false,
        canvaUrl: canvaUrlText.isEmpty ? null : canvaUrlText,
        categories: categories,
        secondCheck: widget.post?.secondCheck ?? false,
        secondCheckAssignees: widget.post?.secondCheckAssignees ?? <String>[],
        status: statusText.isEmpty ? null : statusText,
        fileUrls: widget.post?.fileUrls ?? <String>[],
        authors: widget.post?.authors ?? <String>[],
        authorIds: widget.post?.authorIds ?? <String>[],
        createdTime: widget.post?.createdTime,
        lastEditedTime: widget.post?.lastEditedTime,
      );

      // NotionPostService の upsertPost を呼び出し（新しいファイルURLを渡す）
      await _notionService.upsertPost(
        post,
        isUpdate: _isEdit,
        newFileUrls: newFileUrls,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showNotionLinkRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('投稿するにはNotionとの連携が必要です。プロフィール画面から連携してください。'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildImageSection() {
    final hasImage = _selectedImage != null || 
        (_existingImageUrl != null && _existingImageUrl!.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'サムネイル画像',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isSaving ? null : _pickImage,
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: hasImage
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: _selectedImage != null
                              ? Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                )
                              : Image.network(
                                  _existingImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                                ),
                        ),
                        // 削除ボタン
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _isSaving ? null : _removeImage,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        // 変更ボタン
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '変更',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildImagePlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 48,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 8),
        Text(
          'タップして画像を選択',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '推奨: 16:9 の横長画像',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPost = !_isCheckingNotionLink && _isNotionLinked && !_isSaving;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '投稿編集' : '新規投稿'),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: canPost ? _save : (_isNotionLinked ? null : _showNotionLinkRequiredMessage),
                  icon: Icon(
                    Icons.check,
                    color: canPost ? null : Colors.grey,
                  ),
                ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
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

                  // 画像選択セクション
                  _buildImageSection(),

                  // タイトル
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'タイトル',
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
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

                  // ステータス（固定・編集不可）
                  TextFormField(
                    controller: _statusController,
                    readOnly: true, // ★ 編集不可にする
                    style: TextStyle(color: Colors.grey[700]), // 文字色を少し薄く
                    decoration: InputDecoration( // const を削除（fillColorを使うため）
                      labelText: 'ステータス',
                      border: const OutlineInputBorder(),
                      filled: true, // 背景色をつける
                      fillColor: Colors.grey[200], // グレー背景にして固定項目であることを強調
                    ),
                  ),
                  const SizedBox(height: 16),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: canPost ? _save : (_isNotionLinked ? null : _showNotionLinkRequiredMessage),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canPost ? null : Colors.grey.shade300,
                      foregroundColor: canPost ? null : Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving 
                        ? '保存中...' 
                        : (_isEdit ? '更新する' : '投稿する')),
                  ),
                ],
              ),
            ),
          ),
          // 保存中のオーバーレイ
          if (_isSaving)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '保存中...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
