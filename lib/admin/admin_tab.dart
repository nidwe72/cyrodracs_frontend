import 'package:flutter/material.dart';
import '../app_config_editor/app_config_editor_view.dart';
import 'config_view.dart';

class AdminTab extends StatelessWidget {
  const AdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Config editor'),
              Tab(text: 'Config'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const AppConfigEditorView(),
                ConfigView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
