import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_edit_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String userId;

  const ProfileDetailScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  int _refreshKey = 0;

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchUserProfile() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
  }

  Future<void> _navigateToEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileEditScreen(),
      ),
    );
    // 編集から戻ってきたら画面を更新
    setState(() {
      _refreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        actions: [
          if (isOwnProfile)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _navigateToEdit,
            ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey(_refreshKey),
        future: _fetchUserProfile(),
        builder: (context, snapshot) {
          // ロード中
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // エラー時
          if (snapshot.hasError) {
            return const Center(
              child: Text('エラーが発生しました'),
            );
          }

          // データなし
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('ユーザーが見つかりません'),
            );
          }

          // データあり
          final data = snapshot.data!.data()!;
          final profileImageUrl = data['profileImageUrl'] as String?;
          final displayName = data['displayName'] as String? ?? '名前未設定';
          final school = data['school'] as String? ?? '未設定';
          final grade = data['grade'] as String? ?? '未設定';
          final currentCountry = data['currentCountry'] as String? ?? '未設定';
          final bio = data['bio'] as String? ?? '';
          final mbti = data['mbti'] as String? ?? '';
          final canvaUrl = data['canvaUrl'] as String? ?? '';
          final futureDream = data['futureDream'] as String? ?? '';
          final futureCountry = data['futureCountry'] as String? ?? '';

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24.0),
                // プロフィール画像
                CircleAvatar(
                  radius: 60,
                  backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                      ? NetworkImage(profileImageUrl)
                      : null,
                  child: profileImageUrl == null || profileImageUrl.isEmpty
                      ? const Icon(Icons.person, size: 60)
                      : null,
                ),
                const SizedBox(height: 16.0),
                // 表示名
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16.0),
                // 基本情報（横並び）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.school,
                          label: school,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.grade,
                          label: grade,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: _InfoChip(
                          icon: Icons.location_on,
                          label: currentCountry,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0),
                // 自己紹介
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '自己紹介',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          Text(bio),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16.0),
                // その他の情報
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      if (mbti.isNotEmpty)
                        _InfoRow(label: 'MBTI', value: mbti),
                      if (futureDream.isNotEmpty)
                        _InfoRow(label: '卒後の夢', value: futureDream),
                      if (futureCountry.isNotEmpty)
                        _InfoRow(label: '卒後行きたい国', value: futureCountry),
                      if (canvaUrl.isNotEmpty)
                        _InfoRow(label: 'Canva URL', value: canvaUrl),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 情報チップウィジェット
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4.0),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// 情報行ウィジェット
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

