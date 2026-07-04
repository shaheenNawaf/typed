import 'money_entry.dart';

class Note {
  String id;
  String title;
  String content;
  List<String> tags;
  List<String> imagePaths;
  bool isArchived;
  bool isDeleted;
  String type;
  String? currency;
  bool isPinned;
  DateTime? viewedAt;
  List<MoneyEntry> amounts;
  DateTime createdAt;
  DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    List<String>? imagePaths,
    this.isArchived = false,
    this.isDeleted = false,
    this.type = 'text',
    this.currency,
    this.isPinned = false,
    this.viewedAt,
    List<MoneyEntry>? amounts,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : imagePaths = imagePaths ?? <String>[],
        amounts = amounts ?? <MoneyEntry>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'imagePaths': imagePaths,
        'isArchived': isArchived,
        'isDeleted': isDeleted,
        'type': type,
        'currency': currency,
        'isPinned': isPinned,
        'viewedAt': viewedAt?.toIso8601String(),
        'amounts': amounts.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        tags: (json['tags'] as List).map((e) => e as String).toList(),
        imagePaths: (json['imagePaths'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            <String>[],
        isArchived: (json['isArchived'] as bool?) ?? false,
        isDeleted: (json['isDeleted'] as bool?) ?? false,
        type: (json['type'] as String?) ?? 'text',
        currency: json['currency'] as String?,
        isPinned: (json['isPinned'] as bool?) ?? false,
        viewedAt: json['viewedAt'] != null
            ? DateTime.parse(json['viewedAt'] as String)
            : null,
        amounts: (json['amounts'] as List?)
                ?.map((e) => MoneyEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            <MoneyEntry>[],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );
}
