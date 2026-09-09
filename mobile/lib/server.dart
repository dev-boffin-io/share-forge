// lib/server.dart
// Mirrors core/server.py — same routes, same ignore rules, same "text/plain
// for unknown non-binary types" mimetype quirk (kept intentionally, for
// parity with the desktop version's browser-preview behaviour).

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';

import 'config.dart';
import 'template.dart';

const Set<String> _binaryExts = {
  '.exe', '.dll', '.so', '.dylib', '.bin', '.img', '.iso',
  '.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar',
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.svg',
  '.mp3', '.mp4', '.mkv', '.avi', '.mov', '.wav', '.flac', '.ogg',
  '.ttf', '.woff', '.woff2', '.eot',
  '.db', '.sqlite', '.sqlite3',
};

String _mimeFor(String filename, {bool forceDownload = false}) {
  if (forceDownload) return 'application/octet-stream';
  final ext = p.extension(filename).toLowerCase();
  final guessed = lookupMimeType(filename);
  if (_binaryExts.contains(ext)) {
    return guessed ?? 'application/octet-stream';
  }
  if (guessed != null && guessed.startsWith('text/')) return guessed;
  return 'text/plain; charset=utf-8';
}

class ShareForgeServer {
  final String sharedDir; // absolute path, real filesystem (see README note
                           // on MANAGE_EXTERNAL_STORAGE vs SAF)
  final bool showAll;
  HttpServer? _server;

  ShareForgeServer({required String sharedDir, this.showAll = false})
      : sharedDir = p.normalize(p.absolute(sharedDir));

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return;
    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(_router);
    _server = await shelf_io.serve(handler, defaultHost, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ─── path safety ────────────────────────────────────────────────────────

  /// Resolves a request path against sharedDir, refusing anything that
  /// normalizes outside of it (mirrors _safe_abs in core/server.py).
  String? _safeAbs(String reqPath) {
    final joined = p.normalize(p.join(sharedDir, reqPath));
    if (!p.equals(joined, sharedDir) &&
        !p.isWithin(sharedDir, joined)) {
      return null;
    }
    return joined;
  }

  List<FileEntry> _listDir(String absPath) {
    final dir = Directory(absPath);
    final entries = <FileEntry>[];
    final children = dir.listSync()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final child in children) {
      final name = p.basename(child.path);
      if (!showAll && (ignoredDirs.contains(name) || name.startsWith('.'))) {
        continue;
      }
      final isDir = child is Directory;
      final relPath = p.relative(child.path, from: sharedDir).replaceAll('\\', '/');
      final sizeKb = isDir ? 0 : (File(child.path).lengthSync() ~/ 1024);
      entries.add(FileEntry(
          name: name, isDir: isDir, relPath: relPath, sizeKb: sizeKb));
    }
    return entries;
  }

  // ─── routing ────────────────────────────────────────────────────────────

  FutureOr<Response> _router(Request request) {
    final segments = request.url.pathSegments;

    if (segments.isEmpty) return _handlePath('');

    if (segments.first == 'download_file') {
      return _downloadFile(segments.skip(1).join('/'));
    }
    if (segments.first == 'download_zip') {
      return _downloadZip(segments.skip(1).join('/'));
    }
    if (segments.first == 'upload') {
      if (request.method != 'POST') return Response.notFound('Not found');
      return _uploadFile(request, segments.skip(1).join('/'));
    }
    return _handlePath(segments.join('/'));
  }

  // GET /  and  GET /<req_path>
  Response _handlePath(String reqPath) {
    final absPath = _safeAbs(reqPath);
    if (absPath == null) return Response.notFound('Not found');
    final type = FileSystemEntity.typeSync(absPath);
    if (type == FileSystemEntityType.notFound) return Response.notFound('Not found');

    if (type == FileSystemEntityType.file) {
      final mime = _mimeFor(p.basename(absPath));
      return Response.ok(File(absPath).openRead(),
          headers: {'content-type': mime});
    }

    final files = _listDir(absPath);
    final parentDir = reqPath.isEmpty ? '' : p.dirname(reqPath);
    final rootName = p.basename(sharedDir);
    final html = renderIndexHtml(
      rootName: rootName,
      reqPath: reqPath,
      parentDir: parentDir == '.' ? '' : parentDir,
      files: files,
    );
    return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  // GET /download_file/<req_path> — force download regardless of type
  Response _downloadFile(String reqPath) {
    final absPath = _safeAbs(reqPath);
    if (absPath == null || FileSystemEntity.typeSync(absPath) != FileSystemEntityType.file) {
      return Response.notFound('Not found');
    }
    final filename = p.basename(absPath);
    return Response.ok(
      File(absPath).openRead(),
      headers: {
        'content-type': _mimeFor(filename, forceDownload: true),
        'content-disposition': 'attachment; filename="$filename"',
      },
    );
  }

  // GET /download_zip/  and  GET /download_zip/<req_path>
  //
  // Streams to a temp file on disk via ZipFileEncoder instead of buffering
  // the whole archive in RAM (the desktop version's io.BytesIO approach
  // doesn't scale to large folders on a phone).
  Future<Response> _downloadZip(String reqPath) async {
    final absPath = reqPath.isEmpty ? sharedDir : _safeAbs(reqPath);
    if (absPath == null || FileSystemEntity.typeSync(absPath) != FileSystemEntityType.directory) {
      return Response.notFound('Directory not found');
    }

    final tmpDir = await Directory.systemTemp.createTemp('share_forge_zip_');
    final zipFilename =
        '${reqPath.isEmpty ? 'root_folder' : p.basename(absPath)}.zip';
    final tmpZipPath = p.join(tmpDir.path, zipFilename);

    final encoder = ZipFileEncoder();
    encoder.create(tmpZipPath);
    await _addDirToZip(encoder, absPath, absPath);
    encoder.close();

    final zipFile = File(tmpZipPath);
    final stream = zipFile.openRead().transform<List<int>>(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          sink.close();
          // best-effort cleanup after the response has been read
          tmpDir.delete(recursive: true).catchError((_) {});
        },
      ),
    );

    return Response.ok(
      stream,
      headers: {
        'content-type': 'application/zip',
        'content-disposition': 'attachment; filename="$zipFilename"',
        'content-length': (await zipFile.length()).toString(),
      },
    );
  }

  Future<void> _addDirToZip(
      ZipFileEncoder encoder, String walkRoot, String baseForArcnames) async {
    await for (final entity in Directory(walkRoot).list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (!showAll && (ignoredDirs.contains(name) || name.startsWith('.'))) {
          continue;
        }
        await _addDirToZip(encoder, entity.path, baseForArcnames);
      } else if (entity is File) {
        final arcname = p.relative(entity.path, from: p.dirname(baseForArcnames));
        await encoder.addFile(entity, arcname);
      }
    }
  }

  // POST /upload/  and  POST /upload/<req_path>
  Future<Response> _uploadFile(Request request, String reqPath) async {
    final absPath = reqPath.isEmpty ? sharedDir : _safeAbs(reqPath);
    if (absPath == null || FileSystemEntity.typeSync(absPath) != FileSystemEntityType.directory) {
      return Response(400, body: 'Invalid upload target');
    }

    final form = request.multipart();
    if (form == null) return Response(400, body: 'No file selected');

    String? savedName;
    await for (final part in form.parts) {
      final cd = part.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename="([^"]*)"').firstMatch(cd);
      final filename = match?.group(1);
      if (filename == null || filename.isEmpty) continue;
      savedName = p.basename(filename);
      final outFile = File(p.join(absPath, savedName));
      final sink = outFile.openWrite();
      await sink.addStream(part);
      await sink.close();
    }

    if (savedName == null) return Response(400, body: 'No file selected');
    return Response.found('/${Uri.encodeComponent(reqPath)}');
  }
}
