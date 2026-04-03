import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../data_form_renderer/data_form_renderer_view.dart';
import '../models/data_form.dart';
import 'form_renderer_view.dart';

class BasicTab extends StatefulWidget {
  final String? helloMessage;
  final VoidCallback onHelloPressed;

  const BasicTab({super.key, required this.helloMessage, required this.onHelloPressed});

  @override
  State<BasicTab> createState() => _BasicTabState();
}

class _BasicTabState extends State<BasicTab> {
  DataForm? _form;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchForm();
  }

  Future<void> _fetchForm() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:8080/api/demo-form'));
      if (response.statusCode == 200) {
        setState(() => _form = DataForm.fromJson(jsonDecode(response.body)));
      } else {
        setState(() => _error = 'HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: 0,
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: const TabBar(
                tabs: [
                  Tab(text: 'App playground'),
                  Tab(text: 'Form Renderer'),
                  Tab(text: 'Hello World'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                const DataFormRendererView(),
                _buildFormTab(),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: widget.onHelloPressed,
                        child: const Text('Hello World'),
                      ),
                      if (widget.helloMessage != null) ...[
                        const SizedBox(height: 24),
                        SelectableText(
                          widget.helloMessage!,
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

  Widget _buildFormTab() {
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_form == null) return const Center(child: CircularProgressIndicator());
    return FormRendererView(form: _form!);
  }
}
