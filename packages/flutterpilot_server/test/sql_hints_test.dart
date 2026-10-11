import 'package:flutterpilot_server/src/sql_hints.dart';
import 'package:test/test.dart';

void main() {
  test('reads what SQLite could not find', () {
    expect(
      sqlMissIn(
        'Query failed: SqliteException(1): while preparing statement, '
        'no such column: status, SQL logic error',
      ),
      (isTable: false, name: 'status'),
    );
    expect(sqlMissIn('no such column: s.sync_status'), (
      isTable: false,
      name: 'sync_status',
    ));
    expect(sqlMissIn('no such table: main.sale'), (
      isTable: true,
      name: 'sale',
    ));
    expect(sqlMissIn('near "FORM": syntax error'), isNull);
  });

  test('finds the tables a query reads', () {
    expect(
      tablesIn(
        'SELECT s.id FROM sales s JOIN "sale_items" i ON i.sale_id = s.id '
        'LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id IN '
        '(SELECT sale_id FROM sales)',
      ),
      ['sales', 'sale_items', 'customers'],
    );
    expect(tablesIn('select 1'), isEmpty);
    expect(tablesIn('SELECT * FROM (SELECT 1) x JOIN a ON 1'), ['a']);
  });

  test('names that look like the missing one come first', () {
    expect(closestFirst('status', ['id', 'total', 'sync_status', 'created']), [
      'sync_status',
      'id',
      'total',
      'created',
    ]);
    expect(closestFirst('created_at', ['id', 'created', 'updated_at']), [
      'created',
      'id',
      'updated_at',
    ]);
  });

  test('a long list is cut with the count of the rest', () {
    final hint = schemaHint('tables here', 'x', [
      for (var i = 0; i < 70; i++) 't$i',
    ]);
    expect(hint, startsWith('tables here: t0, t1, '));
    expect(hint, endsWith('… 10 more'));
  });
}
