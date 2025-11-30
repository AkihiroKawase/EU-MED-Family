import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/profile_list_screen.dart';
import 'screens/login_screen.dart';
import 'screens/post_list_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // ロード中
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // ログイン中
          if (snapshot.hasData) {
            return const ProfileListScreen();
          }

          // ログアウト状態
          return const LoginScreen();
        },
      ),
    );
  }
}


class MyHomePage extends StatelessWidget { // StatelessWidgetとして実装
  const MyHomePage({super.key}); // コンストラクタを追加

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ログイン'), // タイトルを追加すると分かりやすいです
      ), // AppBar
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0), // 少し余白を広げました
            child: TextField(
              onChanged: (text) {
                // 入力された文字(text)を使って何か処理をする
                print(text);
              },
              decoration: InputDecoration(
                  labelText: "メールアドレス",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10.0)))), //IputDecoration
            ), //TextField
          ),
          const SizedBox(height: 24),

          // ★ 投稿一覧へ遷移するボタン
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PostListScreen(),
                ),
              );
            },
            child: const Text("投稿一覧へ"),
          ), //Padding
          // 他にもパスワード入力欄やボタンなどをここに追加できます
        ],
      ), // Column
    ); //Sccafold
  }
}