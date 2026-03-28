class TestNode {
  final String code;
  final List<TestNode> children;

  TestNode({required this.code, required this.children});

  factory TestNode.fromJson(Map<String, dynamic> json) {
    return TestNode(
      code: json['code'] as String,
      children: (json['children'] as List<dynamic>)
          .map((c) => TestNode.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
