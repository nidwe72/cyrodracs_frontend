import 'package:flutter/material.dart';
import 'config_view.dart';

class AdminTab extends StatelessWidget {
  const AdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Config'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ConfigView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
