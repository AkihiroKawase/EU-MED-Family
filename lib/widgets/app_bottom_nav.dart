// widgets/app_bottom_nav.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// 画面クラスは実際のパスに合わせて修正してください
import '../screens/post_list_screen.dart';
import '../screens/profile_detail_screen.dart';
import '../screens/profile_list_screen.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
  });

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget nextPage;

    switch (index) {
      case 0:
        // 投稿一覧
        nextPage = const PostListScreen();
        break;
      case 1:
        // 自分のプロフィール詳細
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          // 未ログインなら何かしらの対応（ログイン画面に飛ばすとか）
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ログインしてください')),
          );
          return;
        }
        nextPage = ProfileDetailScreen(userId: user.uid);
        break;
      case 2:
        // ユーザー検索画面
        nextPage = const ProfileListScreen();
        break;
      default:
        nextPage = const PostListScreen();
    }
    // ★ ここが抜けていた！ 実際に画面遷移する処理
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => nextPage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) => _onItemTapped(context, index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.list),
          label: '投稿一覧',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'プロフィール',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.search),
          label: 'ユーザー検索',
        ),
      ],
    );
  }
}