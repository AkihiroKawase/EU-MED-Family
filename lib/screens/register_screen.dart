import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_edit_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _agreedToTerms = false; // 利用規約同意チェックボックス

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // パスワード確認
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パスワードが一致しません')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      // 登録成功後、プロフィール編集画面へ遷移（ナビゲーションスタックをクリア）
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = '登録に失敗しました';
      
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'このメールアドレスは既に使用されています';
          break;
        case 'invalid-email':
          errorMessage = 'メールアドレスの形式が正しくありません';
          break;
        case 'weak-password':
          errorMessage = 'パスワードが弱すぎます（6文字以上必要）';
          break;
        case 'operation-not-allowed':
          errorMessage = 'メール/パスワード認証が無効化されています';
          break;
        default:
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

  /// 利用規約ダイアログを表示
  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('利用規約'),
        content: const SingleChildScrollView(
          child: Text(
            '【EU Med Family 利用規約】\n\n'
            '1. 禁止事項\n'
            '・他者を誹謗中傷するコンテンツの投稿\n'
            '・わいせつ・暴力的なコンテンツの投稿\n'
            '・虚偽の情報の投稿\n'
            '・著作権を侵害するコンテンツの投稿\n'
            '・スパム行為\n\n'
            '2. コンテンツの管理\n'
            '運営は不適切なコンテンツを予告なく削除する権利を有します。\n\n'
            '3. アカウントの停止\n'
            '利用規約に違反したユーザーのアカウントを停止する場合があります。\n\n'
            '4. 免責事項\n'
            'ユーザー間のトラブルについて、運営は責任を負いません。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規登録'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.person_add,
                  size: 80,
                  color: Colors.teal,
                ),
                const SizedBox(height: 32.0),
                const Text(
                  'アカウント作成',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'メールアドレスを入力してください';
                    }
                    if (!value.contains('@')) {
                      return 'メールアドレスの形式が正しくありません';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'パスワード',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    helperText: '6文字以上',
                  ),
                  obscureText: true,
                  enabled: !_isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'パスワードを入力してください';
                    }
                    if (value.length < 6) {
                      return 'パスワードは6文字以上必要です';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'パスワード（確認）',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  enabled: !_isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'パスワードを再入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                // 利用規約同意チェックボックス
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _agreedToTerms,
                      onChanged: _isLoading
                          ? null
                          : (value) {
                              setState(() {
                                _agreedToTerms = value ?? false;
                              });
                            },
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(
                                text: '利用規約',
                                style: const TextStyle(
                                  color: Colors.teal,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _showTermsDialog(),
                              ),
                              const TextSpan(
                                text: 'に同意します（不適切なコンテンツの投稿を禁止します）',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  // チェックボックスがOFFの場合は登録ボタンを無効化
                  onPressed: (_isLoading || !_agreedToTerms) ? null : _register,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          '登録',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                const SizedBox(height: 16.0),
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('ログイン画面に戻る'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

