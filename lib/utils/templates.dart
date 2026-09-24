import 'package:flutter/material.dart';

class NoteTemplate {
  final String name;
  final IconData icon;
  final String title;
  final String content;
  final String preview;
  final List<String> tags;
  final String? type;
  final String? currency;

  const NoteTemplate({
    required this.name,
    required this.icon,
    required this.title,
    required this.content,
    required this.preview,
    this.tags = const [],
    this.type,
    this.currency,
  });
}

List<NoteTemplate> getNoteTemplates() {
  final now = DateTime.now();
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return [
    NoteTemplate(
      name: 'Blank note',
      icon: Icons.note_add_outlined,
      title: 'Untitled',
      content: '',
      preview: 'Start with a clean slate.',
    ),
    NoteTemplate(
      name: 'Daily journal',
      icon: Icons.menu_book_outlined,
      title: 'Journal — $today',
      content: '# $today\n\n'
          '## Mood\n\n\n\n'
          '## Wins\n\n\n\n'
          '## Lessons\n\n\n\n'
          '## Tomorrow\n\n',
      preview: 'Track wins, lessons, and tomorrow\'s focus.',
      tags: ['journal'],
    ),
    NoteTemplate(
      name: 'Meeting notes',
      icon: Icons.groups_outlined,
      title: 'Meeting — $today',
      content: '# Meeting — $today\n\n'
          '## Attendees\n\n\n\n'
          '## Agenda\n\n\n\n'
          '## Notes\n\n\n\n'
          '## Action items\n'
          '- [ ] \n',
      preview: 'Capture attendees, agenda, and action items.',
      tags: ['meeting'],
    ),
    NoteTemplate(
      name: 'Daily expenses',
      icon: Icons.account_balance_wallet_outlined,
      title: 'Expenses — $today',
      content: '# Expenses — $today\n\n'
          '_Track your daily spend._\n',
      preview: 'Log your daily spend with auto-totals.',
      tags: ['finance'],
      type: 'expense',
      currency: 'PHP',
    ),
    NoteTemplate(
      name: 'To-do list',
      icon: Icons.checklist_outlined,
      title: 'Todo — $today',
      content: '- [ ] \n',
      preview: 'Build a checklist and track progress.',
      tags: ['todo'],
      type: 'todo',
    ),
  ];
}
