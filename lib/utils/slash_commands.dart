import 'package:flutter/material.dart';

class SlashCommandDefinition {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<String> aliases;
  final String insertion;

  const SlashCommandDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.aliases,
    required this.insertion,
  });
}

class SlashToken {
  final int start;
  final int end;
  final String query;

  const SlashToken({
    required this.start,
    required this.end,
    required this.query,
  });
}

const slashCommands = <SlashCommandDefinition>[
  SlashCommandDefinition(
    id: 'h1',
    label: 'Heading 1',
    description: 'Large page heading',
    icon: Icons.title,
    aliases: ['heading', 'heading 1'],
    insertion: '# ',
  ),
  SlashCommandDefinition(
    id: 'h2',
    label: 'Heading 2',
    description: 'Section heading',
    icon: Icons.format_size,
    aliases: ['heading 2'],
    insertion: '## ',
  ),
  SlashCommandDefinition(
    id: 'h3',
    label: 'Heading 3',
    description: 'Small section heading',
    icon: Icons.format_size,
    aliases: ['heading 3'],
    insertion: '### ',
  ),
  SlashCommandDefinition(
    id: 'bullet',
    label: 'Bulleted list',
    description: 'Start a bullet list',
    icon: Icons.format_list_bulleted,
    aliases: ['bulleted', 'list'],
    insertion: '- ',
  ),
  SlashCommandDefinition(
    id: 'numbered',
    label: 'Numbered list',
    description: 'Start a numbered list',
    icon: Icons.format_list_numbered,
    aliases: ['ordered'],
    insertion: '1. ',
  ),
  SlashCommandDefinition(
    id: 'todo',
    label: 'Checklist',
    description: 'Add a task checkbox',
    icon: Icons.check_box_outlined,
    aliases: ['checklist', 'task'],
    insertion: '- [ ] ',
  ),
  SlashCommandDefinition(
    id: 'quote',
    label: 'Quote',
    description: 'Add a quote block',
    icon: Icons.format_quote,
    aliases: [],
    insertion: '> ',
  ),
  SlashCommandDefinition(
    id: 'code',
    label: 'Code block',
    description: 'Insert a fenced code block',
    icon: Icons.code,
    aliases: [],
    insertion: '```\n\n```',
  ),
  SlashCommandDefinition(
    id: 'divider',
    label: 'Divider',
    description: 'Add a horizontal divider',
    icon: Icons.horizontal_rule,
    aliases: ['hr', 'line'],
    insertion: '---',
  ),
  SlashCommandDefinition(
    id: 'link',
    label: 'Link',
    description: 'Insert a Markdown link',
    icon: Icons.link,
    aliases: [],
    insertion: '[text](url)',
  ),
  SlashCommandDefinition(
    id: 'table',
    label: 'Table',
    description: 'Insert a formatted table',
    icon: Icons.table_chart_outlined,
    aliases: [],
    insertion: '',
  ),
];

SlashToken? activeSlashToken(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  var start = cursor - 1;
  while (start >= 0 && _isSlashQueryCharacter(text[start])) {
    start--;
  }
  final slash = start;
  if (slash < 0 || slash >= text.length || text[slash] != '/') return null;
  if (slash > 0 && !_isSlashBoundary(text[slash - 1])) return null;
  final query = text.substring(slash + 1, cursor);
  // A whitespace-only query ("/ ") means the user is writing prose after a
  // slash, not searching commands — without this the menu would match all
  // commands and hijack Enter.
  if (query.isNotEmpty && query.trim().isEmpty) return null;
  return SlashToken(start: slash, end: cursor, query: query);
}

List<SlashCommandDefinition> filterSlashCommands(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return slashCommands;
  return slashCommands.where((command) {
    final values = [command.id, command.label, ...command.aliases];
    return values.any((value) => value.toLowerCase().contains(normalized));
  }).toList();
}

String replaceSlashToken(String text, SlashToken token, String replacement) {
  return '${text.substring(0, token.start)}$replacement${text.substring(token.end)}';
}

bool _isSlashBoundary(String character) =>
    character.trim().isEmpty || character == '\n';

bool _isSlashQueryCharacter(String character) =>
    RegExp(r'[A-Za-z0-9_\- ]').hasMatch(character);
