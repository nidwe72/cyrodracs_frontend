import 'package:flutter/material.dart';

class BasicTab extends StatelessWidget {
  final String? helloMessage;
  final VoidCallback onHelloPressed;

  const BasicTab({super.key, required this.helloMessage, required this.onHelloPressed});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hello World'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: onHelloPressed,
                        child: const Text('Hello World'),
                      ),
                      if (helloMessage != null) ...[
                        const SizedBox(height: 24),
                        SelectableText(
                          helloMessage!,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
