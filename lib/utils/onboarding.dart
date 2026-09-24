import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import 'id.dart';

class OnboardingData {
  final List<Note> notes;
  final List<Budget> budgets;

  const OnboardingData({required this.notes, required this.budgets});
}

const String kWelcomeContent =
    '# 👋 Welcome to Typed\n\n'
    'Typed is a private, local-first workspace for notes and finances — '
    'everything stays on your device.\n\n'
    '## ✍️ Notes & Types\n'
    'Create notes, journals, meeting minutes, or to-do lists. '
    'Tap **+** or press `Ctrl+N` and pick a template.\n\n'
    '## 📁 Sidebar\n'
    'Use the sidebar to jump between **Notes**, **Tasks**, **Finance**, '
    '**Meetings**, and **Journal**. Pin important notes for quick access.\n\n'
    '## 💰 Finance\n'
    'Any expense or income note automatically feeds into the **Finance** '
    'dashboard — see totals, trends, categories, and budgets at a glance.\n\n'
    '## 🎨 Themes\n'
    'Open **Settings** (gear icon) to switch fonts, color palettes, '
    'and dark/light mode.\n\n'
    '## ✨ New in Typed\n'
    'The workspace now includes breadcrumbs, a page-details rail, and a '
    'quieter reading-focused layout. On desktop, select a note to open its '
    'details and press `Ctrl+K` or `Cmd+K` to search actions and jump between '
    'sections.\n\n'
    'In a text note, type `/` to insert headings, lists, checklists, quotes, '
    'code blocks, links, tables, and more. In **Tasks**, click any checkbox '
    'to complete it directly from the list.\n\n'
    '## 📚 Workspace guides\n'
    'Read the focused guides for [[Using Notes]], [[Managing Tasks]], '
    '[[Tracking Finance]], and [[Navigating Typed]].\n\n'
    '---\n\n'
    '### Getting started\n'
    '- [ ] Write your first note\n'
    '- [ ] Tag a note with a custom tag\n'
    '- [ ] Visit the **Finance** dashboard\n'
    '- [ ] Try dark mode in **Settings**\n\n'
    '---\n\n'
    '*You can edit or delete this note at any time.*';

const String kWelcomeUpdateMarker = '## 📚 Workspace guides';

const String kWelcomeUpdateContent =
    '## ✨ New in Typed\n'
    'The workspace now includes breadcrumbs, a page-details rail, and a '
    'quieter reading-focused layout. On desktop, select a note to open its '
    'details and press `Ctrl+K` or `Cmd+K` to search actions and jump between '
    'sections.\n\n'
    'In a text note, type `/` to insert headings, lists, checklists, quotes, '
    'code blocks, links, tables, and more. In **Tasks**, click any checkbox '
    'to complete it directly from the list.\n\n'
    '## 📚 Workspace guides\n'
    'Read the focused guides for [[Using Notes]], [[Managing Tasks]], '
    '[[Tracking Finance]], and [[Navigating Typed]].';

List<Note> createWorkspaceGuideNotes([DateTime? timestamp]) {
  final now = timestamp ?? DateTime.now();
  return [
    Note(
      id: '${generateId('n')}_notes_guide',
      title: 'Using Notes',
      content:
          '# Using Notes\n\n'
          'Notes are your flexible workspace for ideas, references, journals, '
          'and meeting records.\n\n'
          '## Start a page\n'
          '- Press `Ctrl+N` or `Cmd+N` to create a blank note.\n'
          '- Use a template when you want a meeting, journal, or structured page.\n'
          '- Add tags such as `project`, `reading`, or `personal` to keep pages easy to find.\n\n'
          '## Write faster\n'
          'Type `/` in the editor for headings, lists, quotes, code blocks, links, '
          'tables, and checklists. Use the command palette with `Ctrl+K` or `Cmd+K` '
          'to jump between workspaces and actions.\n\n'
          '## Connect pages\n'
          'Type `[[` to link another page. Select a note to see linked pages and '
          'backlinks in the details panel.\n\n'
          'Use Preview when you want a clean reading view. Changes are saved locally '
          'on your device.',
      tags: ['guide', 'notes'],
      type: 'text',
      createdAt: now,
      updatedAt: now,
    ),
    Note(
      id: '${generateId('n')}_tasks_guide',
      title: 'Managing Tasks',
      content:
          '# Managing Tasks\n\n'
          'Typed tasks are Markdown checklists that stay quick to edit and easy to review.\n\n'
          '## Create a task list\n'
          '- Create a task template, or type `/todo` in a text note.\n'
          '- Add items using `- [ ] task description`.\n'
          '- Use the Tasks workspace to see task pages together.\n\n'
          '## Complete work\n'
          'Click the checkbox beside any task in the Tasks list or editor. Completed '
          'items are saved immediately and shown with a strike-through.\n\n'
          'Keep planning notes, checklists, and action items together, then use tags '
          'to group work by project or area.',
      tags: ['guide', 'tasks'],
      type: 'todo',
      createdAt: now,
      updatedAt: now,
    ),
    Note(
      id: '${generateId('n')}_finance_guide',
      title: 'Tracking Finance',
      content:
          '# Tracking Finance\n\n'
          'Typed Finance turns expenses and income into a focused dashboard without '
          'sending your data to a server.\n\n'
          '## Add a transaction\n'
          'Open Finance and tap **+**: the dock button on mobile, or the **Expense** / '
          '**Income** buttons in the desktop workspace. '
          'Enter the amount, category, currency, date, and optional details.\n\n'
          '## Read the dashboard\n'
          'Use the period selector for a week, month, year, or all-time view. Use the '
          'currency selector when your entries use more than one currency.\n\n'
          '## Budgets and receipts\n'
          'Create a budget with a category, limit, currency, and period. Existing budgets '
          'can be edited or deleted. On supported devices, scan a receipt and review the '
          'detected amount before applying it.\n\n'
          'Recurring transactions keep their type and schedule, so review the next date '
          'and interval before saving.',
      tags: ['guide', 'finance'],
      type: 'text',
      createdAt: now,
      updatedAt: now,
    ),
    Note(
      id: '${generateId('n')}_navigation_guide',
      title: 'Navigating Typed',
      content:
          '# Navigating Typed\n\n'
          'Typed is organized as a small personal workspace. The sidebar and command '
          'palette are the fastest ways to move around.\n\n'
          '## Sidebar\n'
          'Use Workspace sections for Notes, Tasks, Finance, Meetings, and Journal. '
          'Use Library for Archive and Trash. On desktop, click the logo to expand or '
          'collapse the sidebar.\n\n'
          '## Search and commands\n'
          'Use the search field for page content and press `Ctrl+K` or `Cmd+K` for actions '
          'and workspace navigation.\n\n'
          '## Page details\n'
          'On desktop, select a page to open its details rail. It shows type, dates, tags, '
          'linked pages, backlinks, and page actions.\n\n'
          'Everything is stored locally. Use Settings to change appearance or create a '
          'backup before moving to another device.',
      tags: ['guide', 'workspace'],
      type: 'text',
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

OnboardingData createOnboardingData() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final dateLabel = '${months[now.month - 1]} ${now.day}';

  final welcome = Note(
    id: '${generateId('n')}_welcome',
    title: 'Welcome to Typed',
    content: kWelcomeContent,
    tags: [],
    type: 'text',
    isPinned: true,
    createdAt: now,
    updatedAt: now,
  );

  final sampleFinance = Note(
    id: '${generateId('n')}_finance',
    title: 'Quick expenses — $dateLabel',
    content:
        '# Sample transactions\n\n'
        'These entries show how finance tracking works. '
        'Add your own or delete these to start fresh.\n',
    tags: ['finance'],
    type: 'expense',
    currency: 'PHP',
    amounts: [
      MoneyEntry(
        id: generateId('m'),
        amount: 1500000,
        category: 'Freelance',
        date: yesterday,
        note: 'Freelance project payment',
        type: 'income',
        currency: 'PHP',
        isDemo: true,
      ),
      MoneyEntry(
        id: generateId('m'),
        amount: 18000,
        category: 'Food & Drink',
        date: today,
        note: 'Morning coffee',
        type: 'expense',
        currency: 'PHP',
        isDemo: true,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  return OnboardingData(
    notes: [welcome, ...createWorkspaceGuideNotes(now), sampleFinance],
    budgets: [
      Budget(
        id: generateId('b'),
        category: 'Food & Drink',
        limit: 1000000,
        currency: 'PHP',
        period: 'month',
        isDemo: true,
      ),
    ],
  );
}
