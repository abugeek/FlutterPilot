/// Memory leak check (ROADMAP §5.5): instance counts per class after each
/// round of an action cycle that returns the app to where it started. A
/// class that gains instances every round is kept alive by something.
library;

/// A class whose instance count grew in every round.
class GrowingClass {
  GrowingClass(this.id, this.name, this.library, this.counts);

  /// `classes/123` in the VM service.
  final String id;
  final String name;

  /// Library URI of the class, e.g. `package:app/ui/story.dart`.
  final String? library;

  /// Instance counts: baseline, then after each round.
  final List<int> counts;

  int get growth => counts.last - counts.first;

  /// Grew by the same amount every round, as a leak per cycle does (code
  /// the JIT compiles and caches that fill up grow unevenly).
  bool get steady {
    final first = counts[1] - counts[0];
    for (var i = 2; i < counts.length; i++) {
      if (counts[i] - counts[i - 1] != first) return false;
    }
    return true;
  }

  int get rounds => counts.length - 1;
}

/// Classes that gained at least one instance in every round, largest
/// growth first. [snapshots] are class id -> (name, library, instances),
/// the first being the baseline. A class missing from a snapshot has 0.
List<GrowingClass> growingClasses(
  List<Map<String, ({String name, String? library, int instances})>> snapshots,
) {
  if (snapshots.length < 2) return const [];
  final ids = <String>{for (final s in snapshots) ...s.keys};
  final growing = <GrowingClass>[];
  for (final id in ids) {
    final counts = [for (final s in snapshots) s[id]?.instances ?? 0];
    var every = true;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] <= counts[i - 1]) {
        every = false;
        break;
      }
    }
    if (!every) continue;
    final info = snapshots.lastWhere((s) => s.containsKey(id))[id]!;
    growing.add(GrowingClass(id, info.name, info.library, counts));
  }
  growing.sort((a, b) => b.growth.compareTo(a.growth));
  return growing;
}

/// `_ReadTrackerState ← closure _onRead ← _List[5] ←
/// ChangeNotifier._listeners ← static readEvents`, from `getRetainingPath`
/// elements (leaked object first). Each element's parentListIndex /
/// parentMapKey / parentField says how it holds the element before it.
String describeRetainingPath(List<Map<String, dynamic>> elements) {
  final parts = <String>[];
  for (final e in elements) {
    final name = _objectName(e['value'] as Map? ?? const {});
    final index = e['parentListIndex'];
    final key = e['parentMapKey'];
    final field = e['parentField'];
    parts.add(
      index != null
          ? '$name[$index]'
          : key is Map
          ? '$name[${_objectName(key)}]'
          : field is String
          ? '$name.${_unmangle(field)}'
          : name,
    );
  }
  return parts.join(' ← ');
}

/// Library URIs of the objects on a retaining path: each instance's class
/// library, a static field's owner, a closure's function owner.
Iterable<String> pathLibraries(List<Map<String, dynamic>> elements) sync* {
  String? uriOf(Object? ref) {
    if (ref is! Map) return null;
    if (ref['type'] == '@Library') return ref['uri']?.toString();
    return uriOf(ref['library']) ?? uriOf(ref['owner']);
  }

  for (final e in elements) {
    final value = e['value'];
    if (value is! Map) continue;
    final uri =
        uriOf(value['class']) ??
        uriOf(value['owner']) ??
        uriOf(value['closureFunction']);
    if (uri != null) yield uri;
  }
}

/// `_listeners@816329750` -> `_listeners` (private names carry their
/// library's id).
String _unmangle(String name) => name.replaceAll(RegExp(r'@\d+'), '');

String _objectName(Map value) {
  final type = value['type'];
  if (type == '@Instance') {
    final kind = value['kind'];
    final cls = (value['class'] as Map?)?['name'] ?? kind ?? 'Instance';
    if (kind == 'Closure') {
      final fn = (value['closureFunction'] as Map?)?['name'];
      return fn == null ? 'closure' : 'closure $fn';
    }
    if (kind == 'String') return 'String';
    return '$cls';
  }
  if (type == '@Field') return 'static ${_unmangle('${value['name']}')}';
  if (type == '@Context') return 'Context';
  return '${value['name'] ?? type ?? '?'}';
}
