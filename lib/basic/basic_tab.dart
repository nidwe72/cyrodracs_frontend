import 'package:flutter/material.dart';
import '../models/data_form_element.dart';
import 'form_renderer_view.dart';

const _demoElements = [
  DataFormElement(key: 'firstName', label: 'First Name', type: DataFormElementType.inputString),
  DataFormElement(key: 'lastName',  label: 'Last Name',  type: DataFormElementType.inputString),
  DataFormElement(
    key: 'country',
    label: 'Country',
    type: DataFormElementType.select,
    options: ['Austria', 'France', 'Germany', 'Italy', 'Switzerland'],
  ),
  DataFormElement(key: 'birthDate', label: 'Birth Date', type: DataFormElementType.datePicker),
];

class BasicTab extends StatelessWidget {
  final String? helloMessage;
  final VoidCallback onHelloPressed;

  const BasicTab({super.key, required this.helloMessage, required this.onHelloPressed});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hello World'),
              Tab(text: 'Form Renderer'),
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
                const FormRendererView(elements: _demoElements),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
