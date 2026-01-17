import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_list_screen.dart';
import 'login_screen.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isNewUser = false;
  
  // 画像関連
  File? _selectedProfileImage;
  File? _selectedCoverImage;
  String? _existingProfileImageUrl;
  String? _existingCoverImageUrl;
  
  // コントローラー
  final _displayNameController = TextEditingController();
  final _mbtiController = TextEditingController();
  final _canvaUrlController = TextEditingController();
  final _futureCountryController = TextEditingController();
  final _futureDreamController = TextEditingController();
  final _currentCountryController = TextEditingController();
  final _schoolController = TextEditingController();
  final _gradeController = TextEditingController();
  final _bioController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _mbtiController.dispose();
    _canvaUrlController.dispose();
    _futureCountryController.dispose();
    _futureDreamController.dispose();
    _currentCountryController.dispose();
    _schoolController.dispose();
    _gradeController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!snapshot.exists) {
        setState(() {
          _isNewUser = true;
        });
        return;
      }

      final data = snapshot.data();
      if (data != null && mounted) {
        setState(() {
          _displayNameController.text = data['displayName'] ?? '';
          _mbtiController.text = data['mbti'] ?? '';
          _canvaUrlController.text = data['canvaUrl'] ?? '';
          _futureCountryController.text = data['futureCountry'] ?? '';
          _futureDreamController.text = data['futureDream'] ?? '';
          _currentCountryController.text = data['currentCountry'] ?? '';
          _schoolController.text = data['school'] ?? '';
          _gradeController.text = data['grade'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _existingProfileImageUrl = data['profileImageUrl'];
          _existingCoverImageUrl = data['coverImageUrl'];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('データの読み込みに失敗しました')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage({required bool isProfile}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 50,
      );
      
      if (pickedFile != null) {
        setState(() {
          if (isProfile) {
            _selectedProfileImage = File(pickedFile.path);
          } else {
            _selectedCoverImage = File(pickedFile.path);
          }
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

  Future<String?> _uploadImage(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = await ref.putFile(file);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Image upload error: $e');
      return null;
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしていません')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uid = currentUser.uid;
      String? profileImageUrl = _existingProfileImageUrl;
      String? coverImageUrl = _existingCoverImageUrl;
      
      // プロフィール画像をアップロード
      if (_selectedProfileImage != null) {
        profileImageUrl = await _uploadImage(
          _selectedProfileImage!,
          'users/$uid/profile.jpg',
        );
      }
      
      // カバー画像をアップロード
      if (_selectedCoverImage != null) {
        coverImageUrl = await _uploadImage(
          _selectedCoverImage!,
          'users/$uid/cover.jpg',
        );
      }
      
      final Map<String, dynamic> dataToSave = {
        'displayName': _displayNameController.text,
        'mbti': _mbtiController.text,
        'canvaUrl': _canvaUrlController.text,
        'futureCountry': _futureCountryController.text,
        'futureDream': _futureDreamController.text,
        'currentCountry': _currentCountryController.text,
        'school': _schoolController.text,
        'grade': _gradeController.text,
        'bio': _bioController.text,
        'profileImageUrl': profileImageUrl,
        'coverImageUrl': coverImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (_isNewUser) {
        dataToSave['createdAt'] = FieldValue.serverTimestamp();
      }
      
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        dataToSave,
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存しました')),
        );
        // 新規ユーザーの場合はプロフィール一覧画面へ遷移、既存ユーザーは前の画面に戻る
        if (_isNewUser) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ProfileListScreen()),
            (route) => false,
          );
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// アカウント削除確認ダイアログを表示
  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
          'この操作は取り消せません。アカウントを削除すると、すべてのユーザーデータ（プロフィール、投稿履歴など）が完全に削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  /// アカウント削除処理
  Future<void> _deleteAccount() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしていません')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uid = currentUser.uid;

      // 1. Firestoreデータを先に削除（権限エラー防止のため）
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 2. Firebase Authアカウントを削除
      await currentUser.delete();

      // 3. ログイン画面へ遷移（全画面を破棄）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('アカウントを削除しました')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'アカウントの削除に失敗しました';

      if (e.code == 'requires-recent-login') {
        errorMessage = 'セキュリティ保護のため、一度ログアウトして再ログインしてから実行してください';
      } else {
        errorMessage = 'エラー: ${e.message}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildImageHeader() {
    return SizedBox(
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // カバー画像
          GestureDetector(
            onTap: () => _pickImage(isProfile: false),
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[300],
              ),
              child: _selectedCoverImage != null
                  ? Image.file(
                      _selectedCoverImage!,
                      fit: BoxFit.cover,
                    )
                  : _existingCoverImageUrl != null && _existingCoverImageUrl!.isNotEmpty
                      ? Image.network(
                          _existingCoverImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                        )
                      : _buildCoverPlaceholder(),
            ),
          ),
          // プロフィールアイコン
          Positioned(
            left: 16,
            bottom: 0,
            child: GestureDetector(
              onTap: () => _pickImage(isProfile: true),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _selectedProfileImage != null
                      ? FileImage(_selectedProfileImage!)
                      : _existingProfileImageUrl != null && _existingProfileImageUrl!.isNotEmpty
                          ? NetworkImage(_existingProfileImageUrl!) as ImageProvider
                          : null,
                  child: (_selectedProfileImage == null &&
                          (_existingProfileImageUrl == null || _existingProfileImageUrl!.isEmpty))
                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
              ),
            ),
          ),
          // カバー変更アイコン
          Positioned(
            right: 16,
            bottom: 60,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          ),
          // プロフィール変更アイコン
          Positioned(
            left: 80,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.teal,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, size: 40, color: Colors.grey[500]),
            const SizedBox(height: 8),
            Text(
              'タップしてカバー画像を設定',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール編集'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _onSave,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildImageHeader(),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: '表示名',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _currentCountryController,
                          decoration: const InputDecoration(
                            labelText: '現在の国',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _schoolController,
                          decoration: const InputDecoration(
                            labelText: '大学',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _gradeController,
                          decoration: const InputDecoration(
                            labelText: '学年',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _mbtiController,
                          decoration: const InputDecoration(
                            labelText: 'MBTI',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _futureCountryController,
                          decoration: const InputDecoration(
                            labelText: '卒後行きたい国',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _futureDreamController,
                          decoration: const InputDecoration(
                            labelText: '卒後の夢',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _canvaUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Canva URL',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 16.0),
                        TextFormField(
                          controller: _bioController,
                          decoration: const InputDecoration(
                            labelText: '自己紹介',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 5,
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 32.0),
                        
                        // アカウント削除セクション
                        const Divider(),
                        const SizedBox(height: 24.0),
                        OutlinedButton(
                          onPressed: _isLoading ? null : _showDeleteAccountDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                          ),
                          child: const Text('アカウントを削除する'),
                        ),
                        const SizedBox(height: 32.0),
                        // 利用規約・プライバシーポリシーリンク
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: const Text('利用規約'),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () async {
                            final url = Uri.parse('https://www.notion.so/2ebaae8f429e80678191e66bfaf3e021');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('プライバシーポリシー'),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () async {
                            final url = Uri.parse('https://www.notion.so/280aae8f429e80578482d0fb96dd3e4c');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        const SizedBox(height: 32.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
