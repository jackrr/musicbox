import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

class PersistenceService {
  static PersistenceService? _instance;
  PersistenceService._();
  static PersistenceService get instance =>
      _instance ??= PersistenceService._();

  Future<Directory> _projectsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/projects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(Project project) async {
    final dir  = await _projectsDir();
    final file = File('${dir.path}/${project.id}.json');
    await file.writeAsString(jsonEncode(project.toJson()));
  }

  Future<Project?> load(String id) async {
    final dir  = await _projectsDir();
    final file = File('${dir.path}/$id.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return Project.fromJson(json);
  }

  Future<List<Project>> listAll() async {
    final dir = await _projectsDir();
    final files = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    final projects = <Project>[];
    for (final f in files) {
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        projects.add(Project.fromJson(json));
      } catch (_) {}
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<void> delete(String id) async {
    final dir  = await _projectsDir();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
