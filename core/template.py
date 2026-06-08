# core/template.py

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ root_name }}{% if req_path %} / {{ req_path }}{% endif %}</title>
    <style>
        :root {
            --bg: #0f1117;
            --surface: #1a1d27;
            --border: #2a2d3a;
            --accent: #5c8aff;
            --text: #e2e4ef;
            --muted: #7a7e94;
            --green: #3dba74;
            --orange: #f5a623;
            --dir-color: #f5a623;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Cascadia Code', 'JetBrains Mono', 'Fira Code', monospace;
            background: var(--bg); color: var(--text);
            min-height: 100vh; padding: 24px;
        }
        .container { max-width: 900px; margin: auto; }
        .header {
            display: flex; justify-content: space-between; align-items: center;
            border-bottom: 1px solid var(--border); padding-bottom: 16px; margin-bottom: 20px;
            flex-wrap: wrap; gap: 12px;
        }
        /* ── Breadcrumb ── */
        .breadcrumb {
            display: flex; align-items: center; gap: 4px;
            font-size: 1rem; font-weight: 600; flex-wrap: wrap;
        }
        .breadcrumb a {
            color: var(--accent); text-decoration: none;
        }
        .breadcrumb a:hover { text-decoration: underline; }
        .breadcrumb .sep { color: var(--muted); padding: 0 2px; }
        .breadcrumb .current { color: var(--muted); font-weight: 400; }

        .btn-group { display: flex; gap: 8px; flex-wrap: wrap; }
        .btn {
            padding: 7px 14px; border-radius: 6px; font-size: 0.82rem;
            text-decoration: none; font-family: inherit; font-weight: 500;
            transition: opacity 0.15s; display: inline-flex; align-items: center; gap: 6px;
        }
        .btn:hover { opacity: 0.8; text-decoration: none; }
        .btn-primary { background: var(--accent); color: #fff; }
        .btn-home { background: #1e4a3a; color: var(--green); border: 1px solid #2a6a50; }

        .upload-zone {
            background: var(--surface); border: 1px dashed var(--border);
            border-radius: 8px; padding: 14px 18px; margin-bottom: 20px;
        }
        .upload-zone form { display: flex; gap: 10px; align-items: center; width: 100%; flex-wrap: wrap; }
        .upload-zone input[type="file"] {
            flex-grow: 1; color: var(--text); font-family: inherit;
            font-size: 0.85rem; background: transparent; border: none; outline: none;
        }
        .upload-zone input[type="file"]::file-selector-button {
            background: var(--border); color: var(--text); border: none;
            padding: 6px 12px; border-radius: 4px; cursor: pointer; font-family: inherit; margin-right: 10px;
        }
        .btn-upload {
            background: var(--green); color: #0a1a12; border: none;
            padding: 8px 18px; border-radius: 6px; font-weight: 700; cursor: pointer;
            font-family: inherit; font-size: 0.85rem;
        }
        .btn-upload:hover { opacity: 0.85; }

        .file-list { list-style: none; }
        .file-list li {
            display: flex; justify-content: space-between; align-items: center;
            padding: 11px 14px; border-bottom: 1px solid var(--border); transition: background 0.1s;
        }
        .file-list li:first-child { border-radius: 8px 8px 0 0; background: var(--surface); }
        .file-list li:last-child { border-radius: 0 0 8px 8px; border-bottom: none; }
        .file-list li:hover { background: var(--surface); }
        .item-left { display: flex; align-items: center; gap: 10px; }
        .item-right { display: flex; align-items: center; gap: 8px; }
        a { text-decoration: none; color: var(--accent); }
        a:hover { text-decoration: underline; }
        .dir-link { color: var(--dir-color); font-weight: 600; }
        .back-link { color: var(--muted); }
        .badge {
            font-size: 0.75rem; color: var(--muted); background: var(--border);
            padding: 2px 8px; border-radius: 10px;
        }
        .btn-small {
            font-size: 0.75rem; padding: 3px 10px; border-radius: 4px;
            background: #2a2d3a; color: var(--muted); text-decoration: none; border: 1px solid var(--border);
        }
        .btn-small:hover { background: var(--border); color: var(--text); text-decoration: none; }
        .btn-dl {
            font-size: 0.75rem; padding: 3px 10px; border-radius: 4px;
            background: #1e2f1e; color: var(--green); text-decoration: none; border: 1px solid #2a4a2a;
        }
        .btn-dl:hover { background: #253525; color: var(--green); text-decoration: none; }
        .empty { text-align: center; color: var(--muted); padding: 30px; font-size: 0.9rem; }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <!-- Clickable breadcrumb -->
        <nav class="breadcrumb">
            <a href="/">{{ root_name }}</a>
            {% if req_path %}
                {% set parts = req_path.split('/') %}
                {% for part in parts %}
                    <span class="sep">/</span>
                    {% if not loop.last %}
                        {% set partial = parts[:loop.index] | join('/') %}
                        <a href="{{ url_for('handle_path', req_path=partial) }}">{{ part }}</a>
                    {% else %}
                        <span class="current">{{ part }}</span>
                    {% endif %}
                {% endfor %}
            {% endif %}
        </nav>

        <div class="btn-group">
            <a href="{{ url_for('download_zip', req_path=req_path) }}" class="btn btn-primary">⬇ ZIP Download</a>
            <a href="/" class="btn btn-home">⌂ Home</a>
        </div>
    </div>

    <div class="upload-zone">
        <form action="{{ url_for('upload_file', req_path=req_path) }}" method="post" enctype="multipart/form-data">
            <input type="file" name="file" required>
            <button type="submit" class="btn-upload">↑ Upload</button>
        </form>
    </div>

    <ul class="file-list">
        {% if req_path != '' %}
        <li>
            <div class="item-left">
                <a class="back-link" href="{{ url_for('handle_path', req_path=parent_dir) }}">← Back to parent</a>
            </div>
        </li>
        {% endif %}

        {% for item in files %}
        <li>
            <div class="item-left">
                {% if item.is_dir %}
                    <a class="dir-link" href="{{ url_for('handle_path', req_path=item.rel_path) }}">📂 {{ item.name }}/</a>
                {% else %}
                    <a href="{{ url_for('handle_path', req_path=item.rel_path) }}" target="_blank">📄 {{ item.name }}</a>
                {% endif %}
            </div>
            <div class="item-right">
                {% if item.is_dir %}
                    <a class="btn-small" href="{{ url_for('download_zip', req_path=item.rel_path) }}" title="Download as ZIP">⬇ ZIP</a>
                {% else %}
                    <span class="badge">{{ item.size }} KB</span>
                    <a class="btn-dl" href="{{ url_for('download_file', req_path=item.rel_path) }}" title="Download file">⬇</a>
                {% endif %}
            </div>
        </li>
        {% endfor %}

        {% if not files %}
        <li class="empty">— empty directory —</li>
        {% endif %}
    </ul>
</div>
</body>
</html>"""
