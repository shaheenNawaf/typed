class Budget {
  String id;
  String category;
  double limit;

  Budget({
    required this.id,
    required this.category,
    required this.limit,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'limit': limit,
      };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        category: json['category'] as String,
        limit: (json['limit'] as num).toDouble(),
      );
}
