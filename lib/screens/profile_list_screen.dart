import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_bottom_nav.dart';
import 'profile_detail_screen.dart';
import 'login_screen.dart';
import '../repositories/notion_repository.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({Key? key}) : super(key: key);

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  // 状態変数
  String _searchQuery = '';
  String? _selectedCountry;
  String? _selectedSchool;
  String? _selectedGrade;
  bool _isSyncingNotion = false;

  // 絞り込み候補
  final List<String> _countries = ['指定なし', 'ハンガリー', 'チェコ', 'スロバキア', 'ポーランド', '日本', 'アメリカ'];
  final List<String> _schools = ['指定なし', 'デブレツェン大学', 'ペーチ大学', 'セゲド大学', 'センメルワイス大学'];
  final List<String> _grades = ['指定なし', '1年生', '2年生', '3年生', '4年生', '5年生', '6年生'];
  
  // Repository
  final NotionRepository _notionRepository = NotionRepository();

  Stream<QuerySnapshot<Map<String, dynamic>>> _getUsersStream() {
    // 未認証の場合は空のStreamを返す（ログアウト時のpermission-deniedエラー防止）
    if (FirebaseAuth.instance.currentUser == null) {
      return const Stream.empty();
    }
    
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('users');

    // 絞り込み条件を追加
    if (_selectedCountry != null && _selectedCountry != '指定なし') {
      query = query.where('currentCountry', isEqualTo: _selectedCountry);
    }
    if (_selectedSchool != null && _selectedSchool != '指定なし') {
      query = query.where('school', isEqualTo: _selectedSchool);
    }
    if (_selectedGrade != null && _selectedGrade != '指定なし') {
      query = query.where('grade', isEqualTo: _selectedGrade);
    }

    // キーワード検索
    if (_searchQuery.isNotEmpty) {
      // キーワード検索時は範囲クエリを使用（orderByは使用しない）
      query = query
          .where('displayName', isGreaterThanOrEqualTo: _searchQuery)
          .where('displayName', isLessThanOrEqualTo: _searchQuery + '\uf8ff');
    } else {
      // キーワード検索がない場合は作成日順でソート
      query = query.orderBy('createdAt', descending: true);
    }

    return query.limit(50).snapshots();
  }

  void _navigateToDetail(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileDetailScreen(userId: userId),
      ),
    );
  }

  void _navigateToMyProfile() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _navigateToDetail(currentUser.uid);
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ログアウトに失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _syncNotionUser() async {
    setState(() {
      _isSyncingNotion = true;
    });

    try {
      final notionUserId = await _notionRepository.syncNotionUser();

      if (mounted) {
        if (notionUserId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notion連携が完了しました'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('連携できませんでした'),
              content: const Text(
                'Notionの招待メールを確認してください。\n\n'
                'メールアドレスが一致するNotionユーザーが見つかりませんでした。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('エラー'),
            content: Text('連携中にエラーが発生しました: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingNotion = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メンバーを探す'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索バー
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              children: [
                // キーワード検索
                TextField(
                  decoration: const InputDecoration(
                    hintText: '名前で検索',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12.0),
                // 絞り込みフィルター
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 国フィルター
                      _buildFilterChip(
                        label: '国: ${_selectedCountry ?? '指定なし'}',
                        icon: Icons.location_on,
                        onTap: () => _showFilterDialog(
                          title: '国を選択',
                          items: _countries,
                          currentValue: _selectedCountry,
                          onSelected: (value) {
                            setState(() {
                              _selectedCountry = value == '指定なし' ? null : value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      // 大学フィルター
                      _buildFilterChip(
                        label: '大学: ${_selectedSchool ?? '指定なし'}',
                        icon: Icons.school,
                        onTap: () => _showFilterDialog(
                          title: '大学を選択',
                          items: _schools,
                          currentValue: _selectedSchool,
                          onSelected: (value) {
                            setState(() {
                              _selectedSchool = value == '指定なし' ? null : value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      // 学年フィルター
                      _buildFilterChip(
                        label: '学年: ${_selectedGrade ?? '指定なし'}',
                        icon: Icons.grade,
                        onTap: () => _showFilterDialog(
                          title: '学年を選択',
                          items: _grades,
                          currentValue: _selectedGrade,
                          onSelected: (value) {
                            setState(() {
                              _selectedGrade = value == '指定なし' ? null : value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      // クリアボタン
                      if (_selectedCountry != null ||
                          _selectedSchool != null ||
                          _selectedGrade != null ||
                          _searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _selectedCountry = null;
                              _selectedSchool = null;
                              _selectedGrade = null;
                            });
                          },
                          tooltip: 'すべてクリア',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ユーザーリスト
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _getUsersStream(),
              builder: (context, snapshot) {
                // ロード中
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // エラー時
                if (snapshot.hasError) {
                  final errorMessage = snapshot.error.toString();
                  
                  // ログアウト中のpermission-deniedエラーは無視（ローディング表示）
                  if (errorMessage.contains('permission-denied')) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  
                  final needsIndex = errorMessage.contains('index') || 
                                     errorMessage.contains('requires an index');
                  
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16.0),
                          Text(
                            needsIndex
                                ? 'この検索条件にはFirestoreのインデックスが必要です。\nFirebase Consoleでインデックスを作成してください。'
                                : 'エラーが発生しました',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8.0),
                          Text(
                            errorMessage,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // データなし
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16.0),
                        Text('メンバーがいません'),
                      ],
                    ),
                  );
                }

                // データあり
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final userId = doc.id;
                    final profileImageUrl = data['profileImageUrl'] as String?;
                    final displayName = data['displayName'] as String? ?? '名前未設定';
                    final school = data['school'] as String? ?? '未設定';
                    final grade = data['grade'] as String? ?? '未設定';
                    final currentCountry = data['currentCountry'] as String? ?? '未設定';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: profileImageUrl != null &&
                                  profileImageUrl.isNotEmpty
                              ? NetworkImage(profileImageUrl)
                              : null,
                          child: profileImageUrl == null || profileImageUrl.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('$school / $grade / $currentCountry'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _navigateToDetail(userId),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  // フィルターチップを構築
  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        deleteIcon: const Icon(Icons.arrow_drop_down, size: 18),
        onDeleted: onTap,
      ),
    );
  }

  // フィルター選択ダイアログを表示
  void _showFilterDialog({
    required String title,
    required List<String> items,
    required String? currentValue,
    required Function(String) onSelected,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items.map((item) {
                final isSelected = item == currentValue || 
                                   (item == '指定なし' && currentValue == null);
                return ListTile(
                  title: Text(item),
                  leading: Radio<String>(
                    value: item,
                    groupValue: currentValue ?? '指定なし',
                    onChanged: (value) {
                      if (value != null) {
                        onSelected(value);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  selected: isSelected,
                  onTap: () {
                    onSelected(item);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }
}
