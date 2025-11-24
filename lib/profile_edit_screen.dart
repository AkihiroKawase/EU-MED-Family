import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isNewUser = false;
  
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
    // ローディング開始
    setState(() {
      _isLoading = true;
    });

    try {
      // 現在のユーザーを取得
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        return;
      }

      // Firestoreからユーザードキュメントを取得
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      // ドキュメントが存在しない場合は新規ユーザー
      if (!snapshot.exists) {
        setState(() {
          _isNewUser = true;
        });
        return;
      }

      // データを取得してコントローラーにセット
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

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 現在のユーザーを取得
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしていません')),
      );
      return;
    }

    // ローディング開始
    setState(() {
      _isLoading = true;
    });

    try {
      final uid = currentUser.uid;
      
      // 書き込むデータを定義
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
        'check1': false,
        'check2': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // 新規ユーザーの場合のみ createdAt を設定
      if (_isNewUser) {
        dataToSave['createdAt'] = FieldValue.serverTimestamp();
      }
      
      // Firestoreに保存（merge: true で既存フィールドを保持）
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        dataToSave,
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('エラーが発生しました')),
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: '表示名',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _mbtiController,
                      decoration: const InputDecoration(
                        labelText: 'MBTI',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _canvaUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Canva URL',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _futureCountryController,
                      decoration: const InputDecoration(
                        labelText: '卒後行きたい国',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _futureDreamController,
                      decoration: const InputDecoration(
                        labelText: '卒後の夢',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _currentCountryController,
                      decoration: const InputDecoration(
                        labelText: '現在の国',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _schoolController,
                      decoration: const InputDecoration(
                        labelText: '大学',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _gradeController,
                      decoration: const InputDecoration(
                        labelText: '学年',
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: '自己紹介',
                      ),
                      maxLines: 5,
                      enabled: !_isLoading,
                    ),
                  ],
                ),
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