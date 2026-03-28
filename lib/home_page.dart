import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'admin/admin_tab.dart';
import 'basic/basic_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _helloMessage;

  Future<void> _onHelloPressed() async {
    final response = await http.get(Uri.parse('http://localhost:8080/api/hello'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _helloMessage = 'Hello World (${data['number']})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cyrodracs'),
        ),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'App'),
                Tab(text: 'Admin'),
                Tab(text: 'Basic'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const SizedBox.shrink(),
                  const AdminTab(),
                  BasicTab(
                    helloMessage: _helloMessage,
                    onHelloPressed: _onHelloPressed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
