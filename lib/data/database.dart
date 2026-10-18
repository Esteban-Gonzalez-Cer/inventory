import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const version = 1;
  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
    String? schema,
  }) async {
    final engine = factory ?? databaseFactory;
    final sql =
        schema ?? await rootBundle.loadString('assets/sql/001_schema.sql');
    final databasePath =
        path ?? p.join(await engine.getDatabasesPath(), 'alacena.db');
    return engine.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final block in sql.split('-- statement').skip(1)) {
            if (block.trim().isNotEmpty) await db.execute(block.trim());
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          throw StateError(
            'No existe una migración de $oldVersion a $newVersion.',
          );
        },
      ),
    );
  }
}
