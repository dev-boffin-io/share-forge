# core/server.py
import os
import io
import zipfile
import mimetypes

from flask import Flask, request, send_from_directory, render_template_string, redirect, url_for, send_file

from .config import IGNORED_DIRS, get_self_binary_names
from .template import HTML_TEMPLATE

# Computed once at import time
_SELF_BINARY_NAMES: set[str] = get_self_binary_names()

# Extensions that are truly binary — browser will download
_BINARY_EXTS: set[str] = {
    '.exe', '.dll', '.so', '.dylib', '.bin', '.img', '.iso',
    '.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.svg',
    '.mp3', '.mp4', '.mkv', '.avi', '.mov', '.wav', '.flac', '.ogg',
    '.ttf', '.woff', '.woff2', '.eot',
    '.pyc', '.pyd', '.pyo',
    '.db', '.sqlite', '.sqlite3',
}

def _get_mimetype(filename: str, force_download: bool = False) -> str:
    """
    Determine MIME type:
    - force_download=True  → application/octet-stream (triggers browser download)
    - Known binary ext     → mime from mimetypes or octet-stream
    - Everything else      → text/plain (browser displays inline)
    """
    if force_download:
        return 'application/octet-stream'
    ext = os.path.splitext(filename)[1].lower()
    if ext in _BINARY_EXTS:
        mime, _ = mimetypes.guess_type(filename)
        return mime or 'application/octet-stream'
    mime, _ = mimetypes.guess_type(filename)
    if mime and mime.startswith('text/'):
        return mime
    return 'text/plain; charset=utf-8'


def create_app(shared_dir: str) -> Flask:
    """Flask app factory. shared_dir = root directory to serve."""
    app = Flask(__name__)
    shared_dir = os.path.abspath(shared_dir)

    # ─── helpers ────────────────────────────────────────────────────────────

    def _safe_abs(req_path: str) -> str | None:
        abs_path = os.path.normpath(os.path.join(shared_dir, req_path))
        if not abs_path.startswith(shared_dir):
            return None
        return abs_path

    def _list_dir(abs_path: str, req_path: str) -> list[dict]:
        entries = []
        for name in sorted(os.listdir(abs_path)):
            if name in IGNORED_DIRS or name.startswith('._') or name.startswith('.'):
                continue
            if name in _SELF_BINARY_NAMES:
                continue
            item_path = os.path.join(abs_path, name)
            rel_path = os.path.relpath(item_path, shared_dir).replace('\\', '/')
            is_dir = os.path.isdir(item_path)
            size = os.path.getsize(item_path) // 1024 if not is_dir else 0
            entries.append({'name': name, 'is_dir': is_dir, 'rel_path': rel_path, 'size': size})
        return entries

    # ─── routes ─────────────────────────────────────────────────────────────

    @app.route('/', defaults={'req_path': ''})
    @app.route('/<path:req_path>')
    def handle_path(req_path):
        abs_path = _safe_abs(req_path)
        if abs_path is None or not os.path.exists(abs_path):
            return "Not found", 404

        if os.path.isfile(abs_path):
            mime = _get_mimetype(os.path.basename(abs_path))
            return send_from_directory(
                os.path.dirname(abs_path),
                os.path.basename(abs_path),
                mimetype=mime,
            )

        files = _list_dir(abs_path, req_path)
        parent_dir = os.path.dirname(req_path) if req_path else ''
        return render_template_string(
            HTML_TEMPLATE, files=files, req_path=req_path, parent_dir=parent_dir
        )

    @app.route('/download_file/<path:req_path>')
    def download_file(req_path):
        """Force-download a single file regardless of type."""
        abs_path = _safe_abs(req_path)
        if abs_path is None or not os.path.exists(abs_path) or not os.path.isfile(abs_path):
            return "Not found", 404
        return send_from_directory(
            os.path.dirname(abs_path),
            os.path.basename(abs_path),
            as_attachment=True,
        )

    @app.route('/download_zip/', defaults={'req_path': ''})
    @app.route('/download_zip/<path:req_path>')
    def download_zip(req_path):
        abs_path = _safe_abs(req_path) if req_path else shared_dir
        if abs_path is None or not os.path.exists(abs_path) or not os.path.isdir(abs_path):
            return "Directory not found", 404

        memory_file = io.BytesIO()
        with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(abs_path):
                dirs[:] = [d for d in dirs if d not in IGNORED_DIRS and not d.startswith('.')]
                for file in files:
                    if os.path.basename(file) in _SELF_BINARY_NAMES:
                        continue
                    file_path = os.path.join(root, file)
                    if req_path == '':
                        arcname = os.path.relpath(file_path, shared_dir)
                    else:
                        folder_name = os.path.basename(abs_path)
                        arcname = os.path.join(folder_name, os.path.relpath(file_path, abs_path))
                    zf.write(file_path, arcname)

        memory_file.seek(0)
        zip_filename = f"{os.path.basename(abs_path) if req_path else 'root_folder'}.zip"
        return send_file(memory_file, download_name=zip_filename, as_attachment=True)

    @app.route('/upload/', defaults={'req_path': ''}, methods=['POST'])
    @app.route('/upload/<path:req_path>', methods=['POST'])
    def upload_file(req_path):
        abs_path = _safe_abs(req_path) if req_path else shared_dir
        if abs_path is None or not os.path.isdir(abs_path):
            return "Invalid upload target", 400

        file = request.files.get('file')
        if not file or file.filename == '':
            return "No file selected", 400

        filename = os.path.basename(file.filename)
        file.save(os.path.join(abs_path, filename))
        return redirect(url_for('handle_path', req_path=req_path))

    return app
