import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<void> main() async {
  // main関数はOKです
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// MyAppクラスもOKです
class MyApp extends StatelessWidget {
  const MyApp({super.key}); // コンストラクタに super.key を追加すると良いでしょう

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: MyHomePage(), // constを外すか、MyHomePageのコンストラクタをconstにする
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
          ) //Padding
          // 他にもパスワード入力欄やボタンなどをここに追加できます
        ],
      ), // Column
    ); //Sccafold
  }
}