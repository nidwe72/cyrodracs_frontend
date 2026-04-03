import 'package:flutter/material.dart';
import 'app_view.dart';

class AppTab extends StatelessWidget {
  const AppTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'App'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AppView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
