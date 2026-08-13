import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

/// A simple notes table so AI agents can demo `query_drift_db` and
/// `list_drift_tables` against a real Drift database.
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
}

/// Tags allow AI agents to run JOIN queries, showing richer SQL support.
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
}

/// Many-to-many join table.
class NoteTags extends Table {
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Notes, Tags, NoteTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // -- Notes -----------------------------------------------------------------

  Future<List<Note>> getAllNotes() =>
      (select(notes)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<int> insertNote(String title, String body) =>
      into(notes).insert(NotesCompanion.insert(title: title, body: body));

  Future<void> deleteNote(int id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  Future<void> togglePin(int id, bool pinned) =>
      (update(notes)..where((t) => t.id.equals(id))).write(
        NotesCompanion(pinned: Value(pinned)),
      );

  /// Seed demo rows so AI agents have something to query on first open.
  Future<void> seedIfEmpty() async {
    final existing = await getAllNotes();
    if (existing.isNotEmpty) return;
    await insertNote(
      'Welcome to FlutterPilot',
      'AI agents can query this DB using query_drift_db.',
    );
    await insertNote('SQL Tip', 'Try: SELECT * FROM notes WHERE pinned = 1');
    await insertNote(
      'JOIN Demo',
      'Try: SELECT n.title, t.name FROM notes n JOIN note_tags nt ON nt.note_id = n.id JOIN tags t ON t.id = nt.tag_id',
    );

    // Seed tags
    final ideaTagId = await into(
      tags,
    ).insert(TagsCompanion.insert(name: 'idea'));
    final demoTagId = await into(
      tags,
    ).insert(TagsCompanion.insert(name: 'demo'));
    final notes = await getAllNotes();
    if (notes.length >= 2) {
      await into(
        noteTags,
      ).insert(NoteTagsCompanion.insert(noteId: notes[0].id, tagId: ideaTagId));
      await into(
        noteTags,
      ).insert(NoteTagsCompanion.insert(noteId: notes[1].id, tagId: demoTagId));
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'fp_example.db'));
    return NativeDatabase.createInBackground(file);
  });
}
