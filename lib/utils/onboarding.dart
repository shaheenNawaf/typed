import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';

class OnboardingData {
  final List<Note> notes;
  final List<Budget> budgets;

  const OnboardingData({required this.notes, required this.budgets});
}

const String kWelcomeContent = '# 👋 Welcome to Typed\n\n'
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
    '---\n\n'
    '### Getting started\n'
    '- [ ] Write your first note\n'
    '- [ ] Tag a note with a custom tag\n'
    '- [ ] Visit the **Finance** dashboard\n'
    '- [ ] Try dark mode in **Settings**\n\n'
    '---\n\n'
    '*You can edit or delete this note at any time.*';

OnboardingData createOnboardingData() {
  final now = DateTime.now();
  final ts = now.millisecondsSinceEpoch;
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final dateLabel = '${months[now.month - 1]} ${now.day}';

  final welcome = Note(
    id: 'n${ts}_welcome',
    title: 'Welcome to Typed',
    content: kWelcomeContent,
    tags: [],
    type: 'text',
    isPinned: true,
    createdAt: now,
    updatedAt: now,
  );

  final sampleFinance = Note(
    id: 'n${ts}_finance',
    title: 'Quick expenses — $dateLabel',
    content: '# Sample transactions\n\n'
        'These entries show how finance tracking works. '
        'Add your own or delete these to start fresh.\n',
    tags: ['finance'],
    type: 'expense',
    currency: 'PHP',
    amounts: [
      MoneyEntry(
        id: 'm${ts}_income',
        amount: 15000,
        category: 'Freelance',
        date: yesterday,
        note: 'Freelance project payment',
        type: 'income',
        currency: 'PHP',
      ),
      MoneyEntry(
        id: 'm${ts}_expense',
        amount: 180,
        category: 'Food & Drink',
        date: today,
        note: 'Morning coffee',
        type: 'expense',
        currency: 'PHP',
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );

  return OnboardingData(
    notes: [welcome, sampleFinance],
    budgets: [
      Budget(
        id: 'b${ts}_food',
        category: 'Food & Drink',
        limit: 10000,
      ),
    ],
  );
}
