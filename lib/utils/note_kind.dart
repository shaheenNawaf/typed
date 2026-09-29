import '../models/note.dart';

/// True for the two note types that hold money entries.
///
/// `Note.type` has no single 'finance' value: a finance note is typed
/// `'expense'` or `'income'`, which also seeds the default direction of its
/// add form. Per-entry `MoneyEntry.type` overrides the note when present.
///
/// This is the ONLY place that predicate may live. The loose
/// `type != 'text'` check it replaces also matched `'todo'`, so a task note
/// carrying amounts leaked into finance totals, the CSV export, the finance
/// widget and budget alerts.
bool isFinanceType(String? type) =>
    type == 'expense' || type == 'income';

/// True when [n] is a finance note, ignoring archive/trash state.
bool isFinanceNote(Note n) => isFinanceType(n.type);

/// True when [n] is a finance note that should count toward totals: not
/// archived and not in the trash. This is the predicate every aggregation
/// site must use.
bool isVisibleFinanceNote(Note n) =>
    isFinanceNote(n) && !n.isArchived && !n.isDeleted;