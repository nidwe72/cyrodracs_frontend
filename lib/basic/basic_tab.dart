import 'package:flutter/material.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';
import 'form_renderer_view.dart';

const _demoForm = DataForm(elements: [
  // Row 1: First Name, Last Name
  DataFormElement(key: 'firstName', label: 'First Name', type: DataFormElementType.inputString, cols: 6),
  DataFormElement(key: 'lastName', label: 'Last Name', type: DataFormElementType.inputString, cols: 6),

  // Row 2: Email, Password
  DataFormElement(key: 'email', label: 'Email', type: DataFormElementType.inputEmail, cols: 6, breakBefore: true),
  DataFormElement(key: 'password', label: 'Password', type: DataFormElementType.inputPassword, cols: 6),

  // Row 3: Birth Date, Preferred Time
  DataFormElement(key: 'birthDate', label: 'Birth Date', type: DataFormElementType.datePicker, cols: 6, breakBefore: true),
  DataFormElement(key: 'prefTime', label: 'Preferred Time', type: DataFormElementType.timePicker, cols: 6),

  // Row 4: Appointment (date+time), Vacation (date range)
  DataFormElement(key: 'appointment', label: 'Appointment', type: DataFormElementType.dateTimePicker, cols: 6, breakBefore: true),
  DataFormElement(key: 'vacation', label: 'Vacation', type: DataFormElementType.dateRangePicker, cols: 6),

  // Row 5: Country (select), Languages (multi-select)
  DataFormElement(
    key: 'country',
    label: 'Country',
    type: DataFormElementType.select,
    options: ['Austria', 'France', 'Germany', 'Italy', 'Switzerland'],
    cols: 6,
    breakBefore: true,
  ),
  DataFormElement(
    key: 'languages',
    label: 'Languages',
    type: DataFormElementType.multiSelect,
    options: ['English', 'German', 'French', 'Spanish', 'Italian'],
    cols: 6,
  ),

  // Row 6: Age (number), Satisfaction (rating)
  DataFormElement(key: 'age', label: 'Age', type: DataFormElementType.inputNumber, cols: 6, breakBefore: true),
  DataFormElement(key: 'satisfaction', label: 'Satisfaction', type: DataFormElementType.rating, cols: 6),

  // Row 7: Experience (slider), Active (toggle)
  DataFormElement(key: 'experience', label: 'Experience (years)', type: DataFormElementType.slider, cols: 6, breakBefore: true, min: 0, max: 30),
  DataFormElement(key: 'active', label: 'Active', type: DataFormElementType.toggle, cols: 6),

  // Row 8: Newsletter (checkbox)
  DataFormElement(key: 'newsletter', label: 'Newsletter', type: DataFormElementType.checkbox, cols: 6, breakBefore: true),

  // Row 9: Salutation (radio), Interests (checkbox group)
  DataFormElement(
    key: 'salutation',
    label: 'Salutation',
    type: DataFormElementType.radioGroup,
    options: ['Mr', 'Ms', 'Dr'],
    cols: 6,
    breakBefore: true,
  ),
  DataFormElement(
    key: 'interests',
    label: 'Interests',
    type: DataFormElementType.checkboxGroup,
    options: ['Sports', 'Music', 'Travel', 'Technology'],
    cols: 6,
  ),

  // Row 10: Notes (textarea, full width)
  DataFormElement(key: 'notes', label: 'Notes', type: DataFormElementType.textarea, cols: 12, breakBefore: true, rows: 5),
]);

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
                const FormRendererView(form: _demoForm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
