// ── State ─────────────────────────────────────────────────────────────────────
let currentSession = null;
let currentPhotos = [];
let currentFileKey = null;
let keywords = [];
let locationMeta = { city: null, state: null, country: null, source: null };
let selectedKeys = new Set();
let bulkKeywords = [];
let kwMode = 'add';
let batchStop = false;
let rating = 0;
let uploadedKeys = new Set(JSON.parse(localStorage.getItem('uploadedKeys') || '[]'));
let appSettings = JSON.parse(localStorage.getItem('appSettings') || '{}');
let viewerRotation = 0; // degrees, visual-only

// ── Utils ─────────────────────────────────────────────────────────────────────
function showToast(msg, type = 'success') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = `toast show ${type}`;
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.className = 'toast', 3000);
}

async function api(method, url, body) {
  const opts = { method, headers: {} };
  if (body) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
  const res = await fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Status ────────────────────────────────────────────────────────────────────
async function checkStatus() {
  const bar = document.getElementById('status-bar');
  const txt = document.getElementById('status-text');
  try {
    const s = await api('GET', '/api/status');
    if (s.ok) {
      bar.className = 'ok';
      const settings = await api('GET', '/api/settings').catch(() => ({}));
      txt.textContent = settings.ollamaModel || s.models[0] || '?';
    } else {
      bar.className = 'err';
      txt.textContent = 'Ollama not running';
    }
  } catch {
    bar.className = 'err';
    txt.textContent = 'Ollama unreachable';
  }
}

// ── Sessions ──────────────────────────────────────────────────────────────────
async function loadSessions() {
  const list = document.getElementById('sessions-list');
  const sessions = await api('GET', '/api/sessions');
  list.innerHTML = '';
  if (!sessions.length) {
    list.innerHTML = '<div class="empty-state"><div class="big">📂</div><p>No sessions found</p></div>';
    return;
  }
  for (const s of sessions) {
    const el = document.createElement('div');
    el.className = 'session-item';
    el.dataset.key = s.folderKey;
    el.innerHTML = `
      <div class="session-date" style="display:flex;align-items:center;gap:4px">
        ${escHtml(s.date)}${s.label ? ' · ' + escHtml(s.label) : ''}
        <button class="session-rename-btn" title="Rename session">✏️</button>
      </div>
      <div class="session-meta">
        <span class="session-label">${escHtml(s.label || s.date)}</span>
        <span class="session-progress none" data-folder="${s.folderKey}">${s.photoCount > 0 ? s.photoCount + ' photos' : 'no exports yet'}</span>
      </div>`;
    el.querySelector('.session-rename-btn').addEventListener('click', (e) => {
      e.stopPropagation();
      startSessionRename(s, el);
    });
    el.onclick = () => selectSession(s, el);
    list.appendChild(el);
  }
}

// ── Session notes strip ───────────────────────────────────────────────────────
let notesSaveTimer = null;

document.getElementById('notes-strip-header').addEventListener('click', () => {
  const body = document.getElementById('notes-strip-body');
  const arrow = document.getElementById('notes-strip-arrow');
  const open = body.classList.contains('open');
  body.classList.toggle('open', !open);
  arrow.classList.toggle('open', !open);
  if (!open) document.getElementById('session-notes-input').focus();
});

document.getElementById('session-notes-input').addEventListener('input', () => {
  clearTimeout(notesSaveTimer);
  document.getElementById('notes-strip-saved').textContent = '';
  notesSaveTimer = setTimeout(async () => {
    if (!currentSession) return;
    await api('POST', `/api/session-notes/${currentSession.folderKey}`,
      { text: document.getElementById('session-notes-input').value }
    ).catch(() => {});
    document.getElementById('notes-strip-saved').textContent = 'saved';
  }, 800);
});

function showNotesStrip(text) {
  document.getElementById('notes-strip').classList.remove('hidden');
  document.getElementById('session-notes-input').value = text || '';
  document.getElementById('notes-strip-saved').textContent = '';
}

async function selectSession(session, el) {
  document.querySelectorAll('.session-item').forEach(e => e.classList.remove('active'));
  el.classList.add('active');
  currentSession = session;
  document.getElementById('toolbar-title').textContent = `${session.date}${session.label ? ' · ' + session.label : ''}`;
  document.getElementById('view-mode-toggle').classList.remove('hidden');

  document.getElementById('btn-view-edited').classList.toggle('active', viewMode === 'edited');
  document.getElementById('btn-view-originals').classList.toggle('active', viewMode === 'originals');
  document.getElementById('btn-enrich-all').disabled = false;
  document.getElementById('btn-enrich-all').classList.toggle('hidden', viewMode === 'originals');
  document.getElementById('btn-select-all').classList.toggle('hidden', viewMode === 'originals');

  const { text } = await api('GET', `/api/session-notes/${session.folderKey}`);
  showNotesStrip(text);

  clearSelection();
  closePanel();
  if (viewMode === 'edited') await loadPhotos(session.folderKey);
  else await loadOriginals(session.folderKey);
}

// ── Photos ────────────────────────────────────────────────────────────────────
async function loadPhotos(folderKey) {
  const gallery = document.getElementById('gallery');
  gallery.innerHTML = '<div class="empty-state"><div class="big">⏳</div><p>Loading…</p></div>';
  currentPhotos = await api('GET', `/api/photos/${folderKey}`);
  renderGallery();
  updateToolbarStats();
}

function updateToolbarStats() {
  const total = currentPhotos.length;
  const enriched = currentPhotos.filter(p => p.meta.title && p.meta.description).length;
  const statsEl = document.getElementById('toolbar-stats');
  if (!total) { statsEl.textContent = ''; return; }
  statsEl.textContent = `${enriched}/${total} enriched`;

  if (currentSession) {
    const badge = document.querySelector(`.session-progress[data-folder="${currentSession.folderKey}"]`);
    if (badge) {
      badge.textContent = `${enriched}/${total}`;
      badge.className = `session-progress ${enriched === total ? 'done' : enriched > 0 ? 'partial' : 'none'}`;
    }
  }
}

function renderGallery() {
  const gallery = document.getElementById('gallery');
  gallery.innerHTML = '';
  if (!currentPhotos.length) {
    gallery.innerHTML = '<div class="empty-state"><div class="big">🖼</div><p>No photos</p></div>';
    return;
  }
  for (const p of currentPhotos) {
    const hasTitle = !!p.meta.title;
    const hasDesc = !!p.meta.description;
    const enriched = hasTitle && hasDesc;
    const selected = selectedKeys.has(p.fileKey);
    const isActive = currentFileKey === p.fileKey;
    const isUploaded = uploadedKeys.has(p.fileKey);

    let cls = 'photo-card';
    if (selected) cls += ' selected';
    else if (enriched) cls += ' enriched';
    if (isActive && !selected) cls += ' active';

    const dotCls = enriched ? 'enriched' : hasTitle ? 'partial' : 'none';
    const titleHtml = hasTitle
      ? `<div class="photo-title-preview">${escHtml(p.meta.title)}</div>`
      : '';
    const locHtml = p.meta.location
      ? `<span class="photo-loc-tag">${escHtml(p.meta.location)}</span>`
      : '';
    const uploadedBadge = isUploaded ? '<span class="card-uploaded-badge">✓</span>' : '';
    const ratingBadge = p.meta.rating ? `<span class="card-rating">${'★'.repeat(p.meta.rating)}</span>` : '';

    const card = document.createElement('div');
    card.className = cls;
    card.dataset.key = p.fileKey;
    card.innerHTML = `
      <div class="card-check"></div>
      ${uploadedBadge}
      ${ratingBadge}
      <img class="photo-thumb" src="/api/image/${p.fileKey}?size=thumb" loading="lazy" alt="${escHtml(p.fileName)}" />
      <div class="photo-info">
        <div class="photo-name">${escHtml(p.fileName)}</div>
        ${titleHtml}
        <div class="photo-tags-row">
          <span class="photo-status-dot ${dotCls}" title="${enriched ? 'Enriched' : hasTitle ? 'Partial' : 'No metadata'}"></span>
          ${locHtml}
        </div>
      </div>`;

    card.querySelector('.card-check').addEventListener('click', e => { e.stopPropagation(); toggleSelect(p.fileKey); });
    card.addEventListener('click', () => openDetail(p));
    gallery.appendChild(card);
  }
}

// ── Selection ─────────────────────────────────────────────────────────────────
function updateCardClasses(fileKey) {
  const card = document.querySelector(`.photo-card[data-key="${CSS.escape(fileKey)}"]`);
  if (!card) return;
  const p = currentPhotos.find(x => x.fileKey === fileKey);
  if (!p) return;
  const enriched = !!(p.meta.title && p.meta.description);
  const selected = selectedKeys.has(fileKey);
  const isActive = currentFileKey === fileKey;
  let cls = 'photo-card';
  if (selected) cls += ' selected';
  else if (enriched) cls += ' enriched';
  if (isActive && !selected) cls += ' active';
  card.className = cls;
}

function toggleSelect(fileKey) {
  if (selectedKeys.has(fileKey)) selectedKeys.delete(fileKey);
  else selectedKeys.add(fileKey);
  updateCardClasses(fileKey);
  updateSelectionUI();
}

function clearSelection() {
  selectedKeys.clear();
  updateSelectionUI();
}

function updateSelectionUI() {
  const n = selectedKeys.size;
  const selToolbar = document.getElementById('sel-toolbar');
  if (n > 0) {
    selToolbar.classList.remove('hidden');
    document.getElementById('sel-count').textContent = `${n} selected`;
    document.getElementById('bulk-apply-count').textContent = n;
  } else {
    selToolbar.classList.add('hidden');
    if (document.getElementById('view-bulk').style.display !== 'none') closePanel();
  }
}

document.getElementById('btn-select-all').onclick = () => {
  currentPhotos.forEach(p => selectedKeys.add(p.fileKey));
  updateSelectionUI();
  currentPhotos.forEach(p => updateCardClasses(p.fileKey));
};
document.getElementById('btn-deselect-all').onclick = () => {
  const keys = [...selectedKeys];
  clearSelection();
  keys.forEach(k => updateCardClasses(k));
};
document.getElementById('btn-edit-selected').onclick = openBulkEdit;

// ── Panel switching ───────────────────────────────────────────────────────────
function showPanel(view) {
  document.getElementById('right-panel').classList.remove('hidden');
  document.getElementById('view-single').style.display = view === 'single' ? 'flex' : 'none';
  document.getElementById('view-bulk').style.display  = view === 'bulk'   ? 'flex' : 'none';
}

function closePanel() {
  currentFileKey = null;
  document.getElementById('right-panel').classList.add('hidden');
  document.querySelectorAll('.photo-card').forEach(c => c.classList.remove('active'));
}

// ── Rating ────────────────────────────────────────────────────────────────────
function renderRating() {
  document.querySelectorAll('#stars-row .star').forEach(s => {
    s.classList.toggle('on', parseInt(s.dataset.v) <= rating);
  });
  const clearBtn = document.getElementById('rating-clear');
  if (clearBtn) clearBtn.style.display = rating > 0 ? '' : 'none';
}

document.querySelectorAll('#stars-row .star').forEach(s => {
  s.addEventListener('click', () => { rating = parseInt(s.dataset.v); renderRating(); });
  s.addEventListener('mouseenter', () => {
    const v = parseInt(s.dataset.v);
    document.querySelectorAll('#stars-row .star').forEach(st => st.classList.toggle('on', parseInt(st.dataset.v) <= v));
  });
  s.addEventListener('mouseleave', () => renderRating());
});

document.getElementById('rating-clear').onclick = () => { rating = 0; renderRating(); };

// ── Fullscreen ────────────────────────────────────────────────────────────────
function renderFullscreenExif(meta) {
  const el = document.getElementById('fullscreen-exif');
  if (!meta) { el.classList.add('hidden'); return; }

  const parts = [];
  const add = (label, val) => val && parts.push(
    `${label ? `<span class="fx-lbl">${label}</span>` : ''}${escHtml(String(val))}`
  );

  if (meta.dateTimeOriginal) add('', meta.dateTimeOriginal.toString().slice(0, 16).replace('T', ' '));
  if (meta.make || meta.model) add('', [meta.make, meta.model].filter(Boolean).join(' '));
  if (meta.focalLength) add('', meta.focalLength);
  if (meta.aperture)    add('f/', meta.aperture);
  if (meta.shutterSpeed) add('', meta.shutterSpeed + 's');
  if (meta.iso)         add('ISO ', meta.iso);
  if (meta.location)    add('📍 ', meta.location);
  if (meta.rating)      add('', '★'.repeat(meta.rating));

  if (!parts.length) { el.classList.add('hidden'); return; }
  el.innerHTML = parts.join('<span class="fx-sep"> · </span>');
  el.classList.remove('hidden');
}

document.getElementById('detail-preview').addEventListener('click', () => {
  if (!currentFileKey) return;
  const photo = currentPhotos.find(p => p.fileKey === currentFileKey);
  document.getElementById('fullscreen-img').src = `/api/image/${currentFileKey}?size=preview`;
  document.getElementById('fullscreen-caption').textContent = photo ? photo.fileName : '';
  renderFullscreenExif(photo ? photo.meta : null);
  document.getElementById('fullscreen-overlay').classList.remove('hidden');
});

document.getElementById('fullscreen-overlay').addEventListener('click', closeFullscreen);
document.getElementById('btn-rotate-ccw').addEventListener('click', e => { e.stopPropagation(); rotateViewer(-90); });
document.getElementById('btn-rotate-cw').addEventListener('click',  e => { e.stopPropagation(); rotateViewer(90); });

function rotateViewer(delta) {
  viewerRotation = (viewerRotation + delta + 360) % 360;
  const img = document.getElementById('fullscreen-img');
  const rotated = viewerRotation % 180 !== 0;
  img.style.transform = viewerRotation ? `rotate(${viewerRotation}deg)` : '';
  img.style.maxWidth  = rotated ? '100vh' : '';
  img.style.maxHeight = rotated ? '100vw' : '';
}

function closeFullscreen() {
  document.getElementById('fullscreen-overlay').classList.add('hidden');
  document.getElementById('fullscreen-img').src = '';
  document.getElementById('fullscreen-img').style.transform = '';
  document.getElementById('fullscreen-img').style.maxWidth  = '';
  document.getElementById('fullscreen-img').style.maxHeight = '';
  document.getElementById('fullscreen-exif').classList.add('hidden');
  viewerRotation = 0;
}

// ── Upload status ─────────────────────────────────────────────────────────────
function updateUploadedBtn() {
  const btn = document.getElementById('btn-toggle-uploaded');
  if (!btn) return;
  const isUploaded = currentFileKey && uploadedKeys.has(currentFileKey);
  btn.textContent = isUploaded ? '✓ Uploaded' : '☁ Mark uploaded';
  btn.className = isUploaded ? 'btn-success' : 'btn-secondary';
  btn.style.fontSize = '11px';
}

document.getElementById('btn-toggle-uploaded').onclick = () => {
  if (!currentFileKey) return;
  if (uploadedKeys.has(currentFileKey)) uploadedKeys.delete(currentFileKey);
  else uploadedKeys.add(currentFileKey);
  localStorage.setItem('uploadedKeys', JSON.stringify([...uploadedKeys]));
  updateUploadedBtn();
  renderGallery();
};

// ── Settings ──────────────────────────────────────────────────────────────────
document.getElementById('btn-settings').onclick = async () => {
  // Load server-side settings
  const srv = await api('GET', '/api/settings').catch(() => ({}));
  document.getElementById('settings-camera-root').value = srv.cameraRoot || '';
  document.getElementById('settings-ollama-url').value = srv.ollamaUrl || '';

  // Populate model dropdown from Ollama
  const statusData = await api('GET', '/api/status').catch(() => ({ models: [] }));
  const models = statusData.models || [];
  const currentModel = srv.ollamaModel || '';
  const allModels = (models.includes(currentModel) || !currentModel) ? models : [currentModel, ...models];
  const modelSelect = document.getElementById('settings-ollama-model');
  modelSelect.innerHTML = allModels.length
    ? allModels.map(m => `<option value="${m}"${m === currentModel ? ' selected' : ''}>${m}</option>`).join('')
    : `<option value="${currentModel}">${currentModel || 'No models found — is Ollama running?'}</option>`;

  // Load client-side settings
  document.getElementById('settings-creator').value = appSettings.creator || '';
  document.getElementById('settings-copyright').value = appSettings.copyright || '';
  document.getElementById('settings-modal').classList.remove('hidden');
};

document.getElementById('btn-pick-folder').onclick = async () => {
  const result = await api('GET', '/api/pick-folder').catch(() => ({ path: null }));
  if (result.path) document.getElementById('settings-camera-root').value = result.path;
};

function closeSettingsModal() {
  document.getElementById('settings-modal').classList.add('hidden');
}

document.getElementById('btn-settings-close').onclick = closeSettingsModal;
document.getElementById('btn-settings-cancel').onclick = closeSettingsModal;

document.getElementById('btn-settings-save').onclick = async () => {
  const cameraRoot = document.getElementById('settings-camera-root').value.trim();
  const ollamaUrl = document.getElementById('settings-ollama-url').value.trim();
  const ollamaModel = document.getElementById('settings-ollama-model').value.trim();

  // Save server-side settings
  await api('POST', '/api/settings', { cameraRoot, ollamaUrl, ollamaModel });

  // Save client-side settings
  appSettings.creator = document.getElementById('settings-creator').value.trim();
  appSettings.copyright = document.getElementById('settings-copyright').value.trim();
  localStorage.setItem('appSettings', JSON.stringify(appSettings));

  closeSettingsModal();
  showToast('Settings saved');
  checkStatus();
  loadSessions(); // refresh session list with new camera root
};

// ── Single Detail ─────────────────────────────────────────────────────────────
function openDetail(photo) {
  currentFileKey = photo.fileKey;
  showPanel('single');

  const idx = currentPhotos.findIndex(p => p.fileKey === photo.fileKey);
  document.getElementById('detail-filename').textContent = photo.fileName;
  document.getElementById('detail-nav-pos').textContent = `${idx + 1}/${currentPhotos.length}`;
  document.getElementById('btn-prev').disabled = idx === 0;
  document.getElementById('btn-next').disabled = idx === currentPhotos.length - 1;

  document.getElementById('detail-preview').src = `/api/image/${photo.fileKey}?size=preview`;

  // Originals
  const origRow = document.getElementById('originals-row');
  origRow.innerHTML = '';
  const origs = photo.originals || {};
  if (origs.jpeg || origs.raw) {
    if (origs.jpeg) {
      const b = document.createElement('button');
      b.className = 'orig-btn'; b.textContent = '📷 Original JPEG';
      b.onclick = () => api('POST', `/api/reveal/${origs.jpeg}`).catch(() => {});
      origRow.appendChild(b);
    }
    if (origs.raw) {
      const b = document.createElement('button');
      b.className = 'orig-btn'; b.textContent = '🎞 Original RAW';
      b.onclick = () => api('POST', `/api/reveal/${origs.raw}`).catch(() => {});
      origRow.appendChild(b);
    }
    origRow.classList.remove('hidden');
  } else {
    origRow.classList.add('hidden');
  }

  const m = photo.meta;
  const exifGrid = document.getElementById('exif-grid');
  const items = [
    ['Date', m.dateTimeOriginal || '—'],
    ['Camera', [m.make, m.model].filter(Boolean).join(' ') || '—'],
    ['Focal', m.focalLength || '—'],
    ['f/', m.aperture || '—'],
    ['Shutter', m.shutterSpeed || '—'],
    ['ISO', m.iso || '—'],
  ];
  exifGrid.innerHTML = items.map(([k,v]) =>
    `<div class="exif-item"><span class="key">${k} </span><span class="val">${escHtml(String(v))}</span></div>`
  ).join('');

  document.getElementById('field-title').value = m.title || '';
  document.getElementById('field-description').value = m.description || '';
  document.getElementById('field-location').value = m.location || '';
  document.getElementById('field-notes').value = '';
  locationMeta = { city: null, state: null, country: null, source: m.locationSource || null };
  updateLocBadge(m.locationSource || null);
  keywords = [...(m.keywords || [])];
  renderKeywords();

  // Rating
  rating = m.rating || 0;
  renderRating();

  // Upload status
  updateUploadedBtn();

  document.querySelectorAll('.photo-card').forEach(c => c.classList.toggle('active', c.dataset.key === photo.fileKey));
  const activeCard = document.querySelector(`.photo-card[data-key="${photo.fileKey}"]`);
  activeCard?.scrollIntoView({ block: 'nearest' });
}

// Prev / Next
document.getElementById('btn-prev').onclick = () => {
  const idx = currentPhotos.findIndex(p => p.fileKey === currentFileKey);
  if (idx > 0) openDetail(currentPhotos[idx - 1]);
};
document.getElementById('btn-next').onclick = () => {
  const idx = currentPhotos.findIndex(p => p.fileKey === currentFileKey);
  if (idx < currentPhotos.length - 1) openDetail(currentPhotos[idx + 1]);
};

document.getElementById('btn-close-detail').onclick = closePanel;

// Collapsible EXIF
document.getElementById('exif-toggle').onclick = () => {
  const grid = document.getElementById('exif-grid');
  const arrow = document.getElementById('exif-toggle-arrow');
  const open = !grid.classList.contains('hidden');
  grid.classList.toggle('hidden', open);
  arrow.classList.toggle('open', !open);
};

// ── Dedup buttons ─────────────────────────────────────────────────────────────
document.getElementById('btn-dedup-single').onclick = async () => {
  if (!currentFileKey) return;
  const btn = document.getElementById('btn-dedup-single');
  btn.disabled = true; btn.textContent = '…';
  try {
    const result = await api('POST', '/api/dedup-keywords', { fileKeys: [currentFileKey] });
    const r = result.results[0];
    if (r.removed > 0) {
      const meta = await api('GET', `/api/meta/${currentFileKey}`);
      keywords = meta.keywords || [];
      renderKeywords();
      const idx = currentPhotos.findIndex(p => p.fileKey === currentFileKey);
      if (idx !== -1) currentPhotos[idx].meta = meta;
      showToast(`Removed ${r.removed} duplicate${r.removed > 1 ? 's' : ''}`);
    } else {
      showToast('No duplicates found');
    }
  } catch (err) { showToast(err.message, 'error'); }
  finally { btn.textContent = 'Dedup'; btn.disabled = false; }
};

document.getElementById('btn-dedup-selected').onclick = async () => {
  const keys = [...selectedKeys];
  if (!keys.length) return;
  const btn = document.getElementById('btn-dedup-selected');
  btn.disabled = true; btn.textContent = '…';
  try {
    const result = await api('POST', '/api/dedup-keywords', { fileKeys: keys });
    const totalRemoved = result.results.reduce((s, r) => s + (r.removed || 0), 0);
    const fixed = result.results.filter(r => r.removed > 0).length;
    for (const r of result.results) {
      if (!r.ok || r.removed === 0) continue;
      const idx = currentPhotos.findIndex(p => p.fileKey === r.fileKey);
      if (idx !== -1) currentPhotos[idx].meta = await api('GET', `/api/meta/${r.fileKey}`);
    }
    renderGallery();
    showToast(totalRemoved > 0 ? `Fixed ${fixed} photos, removed ${totalRemoved} duplicates` : 'No duplicates found');
  } catch (err) { showToast(err.message, 'error'); }
  finally { btn.disabled = false; btn.textContent = 'Dedup Tags'; }
};

// ── Location badge ────────────────────────────────────────────────────────────
function updateLocBadge(source) {
  const badge = document.getElementById('loc-badge');
  if (!source) { badge.style.display = 'none'; return; }
  badge.style.display = '';
  badge.className = `loc-badge ${source}`;
  badge.textContent = source === 'gps' ? '📍 GPS' : '🤖 AI';
}

document.getElementById('field-location').addEventListener('input', () => {
  locationMeta = { city: null, state: null, country: null, source: null };
  updateLocBadge(null);
});

// ── Keywords ──────────────────────────────────────────────────────────────────
function renderKeywords() {
  const wrap = document.getElementById('keywords-wrap');
  const input = document.getElementById('keyword-input');
  wrap.innerHTML = '';
  for (const kw of keywords) {
    const tag = document.createElement('span');
    tag.className = 'keyword-tag';
    tag.innerHTML = `${escHtml(kw)}<span class="remove" data-kw="${escHtml(kw)}">×</span>`;
    tag.querySelector('.remove').onclick = e => {
      keywords = keywords.filter(k => k !== e.target.dataset.kw);
      renderKeywords();
    };
    wrap.appendChild(tag);
  }
  wrap.appendChild(input);
  input.value = '';
}

document.getElementById('keyword-input').addEventListener('keydown', e => {
  if (e.key === 'Enter' || e.key === ',') {
    e.preventDefault();
    const val = e.target.value.trim().replace(/,$/, '');
    if (val && !keywords.includes(val)) { keywords.push(val); renderKeywords(); }
    else e.target.value = '';
  }
});

// ── AI Enrich (single) ────────────────────────────────────────────────────────
document.getElementById('btn-ai').onclick = async () => {
  if (!currentFileKey) return;
  const btn = document.getElementById('btn-ai');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span>Analyzing…';
  try {
    const existingLocation = document.getElementById('field-location').value.trim();
    const result = await api('POST', `/api/enrich/${currentFileKey}`, {
      locationHint: existingLocation || undefined,
      notes: document.getElementById('field-notes').value.trim() || undefined,
      sessionNotes: document.getElementById('session-notes-input')?.value.trim() || undefined,
    });
    document.getElementById('field-title').value = result.title;
    document.getElementById('field-description').value = result.description;
    if (!existingLocation && result.location) {
      document.getElementById('field-location').value = result.location;
      locationMeta = { city: result.city || null, state: result.state || null, country: result.country || null, source: result.locationSource };
      updateLocBadge(result.locationSource);
    }
    keywords = result.keywords;
    renderKeywords();
    showToast('AI suggestions ready — review and save');
  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '✨ Enrich';
  }
};

// ── Save (single) ─────────────────────────────────────────────────────────────
document.getElementById('btn-save').onclick = async () => {
  if (!currentFileKey) return;
  const btn = document.getElementById('btn-save');
  btn.disabled = true; btn.textContent = 'Saving…';
  try {
    const locStr = document.getElementById('field-location').value.trim();
    let saveCity = locationMeta.city, saveState = locationMeta.state, saveCountry = locationMeta.country;
    if (locStr && !saveCity && !saveCountry) {
      const parts = locStr.split(',').map(s => s.trim());
      saveCity = parts[0] || null;
      saveCountry = parts[parts.length - 1] || null;
      if (parts.length > 2) saveState = parts[1];
    }
    const result = await api('POST', `/api/save/${currentFileKey}`, {
      title: document.getElementById('field-title').value,
      description: document.getElementById('field-description').value,
      keywords,
      city: saveCity || undefined,
      state: saveState || undefined,
      country: saveCountry || undefined,
      rating: rating || undefined,
      creator: appSettings.creator || undefined,
      copyright: appSettings.copyright || undefined,
    });
    const idx = currentPhotos.findIndex(p => p.fileKey === currentFileKey);
    if (idx !== -1) {
      currentPhotos[idx].meta = result.meta;
      renderGallery();
      updateToolbarStats();
      openDetail(currentPhotos[idx]);
    }
    showToast('Saved to EXIF/XMP');
  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '💾 Save';
  }
};

// ── Bulk Edit ─────────────────────────────────────────────────────────────────
function openBulkEdit() {
  const n = selectedKeys.size;
  if (!n) return;
  showPanel('bulk');
  document.getElementById('bulk-title').textContent = `Editing ${n} photo${n > 1 ? 's' : ''}`;
  document.getElementById('bulk-apply-count').textContent = n;
  document.getElementById('bulk-location').value = '';
  bulkKeywords = [];
  renderBulkKeywords();
  const keys = [...selectedKeys];
  const thumbsEl = document.getElementById('bulk-thumbs');
  thumbsEl.innerHTML = keys.slice(0, 10).map(k => `<img src="/api/image/${k}?size=thumb" />`).join('');
  if (keys.length > 10) thumbsEl.innerHTML += `<span class="more">+${keys.length - 10}</span>`;
}

document.getElementById('btn-close-bulk').onclick = closePanel;

function setKwMode(mode) {
  kwMode = mode;
  document.getElementById('kw-mode-add').classList.toggle('active', mode === 'add');
  document.getElementById('kw-mode-replace').classList.toggle('active', mode === 'replace');
  document.getElementById('kw-mode-hint').textContent = mode === 'add'
    ? "Tags will be added to each photo's existing keywords."
    : "These tags will replace all existing keywords on selected photos.";
}

function renderBulkKeywords() {
  const wrap = document.getElementById('bulk-keywords-wrap');
  const input = document.getElementById('bulk-keyword-input');
  wrap.innerHTML = '';
  for (const kw of bulkKeywords) {
    const tag = document.createElement('span');
    tag.className = 'keyword-tag';
    tag.innerHTML = `${escHtml(kw)}<span class="remove" data-kw="${escHtml(kw)}">×</span>`;
    tag.querySelector('.remove').onclick = e => {
      bulkKeywords = bulkKeywords.filter(k => k !== e.target.dataset.kw);
      renderBulkKeywords();
    };
    wrap.appendChild(tag);
  }
  wrap.appendChild(input);
  input.value = '';
}

document.getElementById('bulk-keyword-input').addEventListener('keydown', e => {
  if (e.key === 'Enter' || e.key === ',') {
    e.preventDefault();
    const val = e.target.value.trim().replace(/,$/, '');
    if (val && !bulkKeywords.includes(val)) { bulkKeywords.push(val); renderBulkKeywords(); }
    else e.target.value = '';
  }
});

document.getElementById('btn-apply-bulk').onclick = async () => {
  const locStr = document.getElementById('bulk-location').value.trim();
  const hasLocation = !!locStr;
  const hasKeywords = bulkKeywords.length > 0;
  if (!hasLocation && !hasKeywords) { showToast('Fill in at least one field', 'error'); return; }

  let city, state, country;
  if (hasLocation) {
    const parts = locStr.split(',').map(s => s.trim());
    city = parts[0] || undefined;
    country = parts[parts.length - 1] || undefined;
    if (parts.length > 2) state = parts[1];
  }

  const btn = document.getElementById('btn-apply-bulk');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span>Applying…';
  try {
    const result = await api('POST', '/api/batch-save', {
      fileKeys: [...selectedKeys], city, state, country,
      keywords: hasKeywords ? bulkKeywords : undefined,
      keywordsMode: kwMode,
    });
    const failed = result.results.filter(r => !r.ok);
    if (failed.length) showToast(`Done with ${failed.length} error(s)`, 'error');
    else showToast(`Applied to ${selectedKeys.size} photos`);

    for (const r of result.results) {
      if (!r.ok) continue;
      const idx = currentPhotos.findIndex(p => p.fileKey === r.fileKey);
      if (idx !== -1) currentPhotos[idx].meta = await api('GET', `/api/meta/${r.fileKey}`);
    }
    renderGallery();
    updateToolbarStats();
    clearSelection();
    closePanel();
  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `Apply to <span id="bulk-apply-count">${selectedKeys.size}</span> photos`;
  }
};

// ── Batch AI Enrich ───────────────────────────────────────────────────────────
document.getElementById('btn-enrich-all').onclick = () => {
  const unenriched = currentPhotos.filter(p => !p.meta.title || !p.meta.description);
  if (!unenriched.length) { showToast('All photos already enriched'); return; }
  runBatch(unenriched);
};
document.getElementById('btn-mark-uploaded').onclick = () => {
  const keys = [...selectedKeys];
  if (!keys.length) return;
  const allUploaded = keys.every(k => uploadedKeys.has(k));
  // Toggle: if all are already uploaded — unmark all, otherwise mark all
  for (const k of keys) {
    if (allUploaded) uploadedKeys.delete(k);
    else uploadedKeys.add(k);
  }
  localStorage.setItem('uploadedKeys', JSON.stringify([...uploadedKeys]));
  updateUploadedBtn();
  renderGallery();
  showToast(allUploaded ? `Unmarked ${keys.length} photos` : `Marked ${keys.length} photos as uploaded`);
};

document.getElementById('btn-enrich-selected').onclick = () => {
  const selected = currentPhotos.filter(p => selectedKeys.has(p.fileKey));
  if (selected.length) runBatch(selected);
};
document.getElementById('btn-stop-batch').onclick = () => { batchStop = true; };

async function runBatch(photos) {
  batchStop = false;
  const bar = document.getElementById('batch-bar');
  const fill = document.getElementById('batch-fill');
  bar.classList.remove('hidden');
  document.getElementById('btn-enrich-all').disabled = true;

  for (let i = 0; i < photos.length; i++) {
    if (batchStop) break;
    const p = photos[i];
    document.getElementById('batch-label').textContent = p.fileName;
    document.getElementById('batch-count').textContent = `${i + 1}/${photos.length}`;
    fill.style.width = `${((i + 1) / photos.length) * 100}%`;
    try {
      const result = await api('POST', `/api/enrich/${p.fileKey}`, {
        locationHint: p.meta.location?.trim() || undefined,
        sessionNotes: document.getElementById('session-notes-input')?.value.trim() || undefined,
      });
      delete result.city; delete result.state; delete result.country;
      await api('POST', `/api/save/${p.fileKey}`, {
        ...result,
        creator: appSettings.creator || undefined,
        copyright: appSettings.copyright || undefined,
      });
      const idx = currentPhotos.findIndex(x => x.fileKey === p.fileKey);
      if (idx !== -1) {
        currentPhotos[idx].meta = await api('GET', `/api/meta/${p.fileKey}`);
        renderGallery();
        updateToolbarStats();
      }
    } catch (err) {
      showToast(`${p.fileName}: ${err.message}`, 'error');
    }
  }
  bar.classList.add('hidden');
  fill.style.width = '0';
  document.getElementById('btn-enrich-all').disabled = false;
  showToast(batchStop ? 'Stopped' : 'Batch complete!');
}

// ── Keyboard shortcuts ────────────────────────────────────────────────────────
document.addEventListener('keydown', e => {
  const tag = e.target.tagName;
  const isInput = tag === 'INPUT' || tag === 'TEXTAREA';

  const fullscreenOpen = !document.getElementById('fullscreen-overlay').classList.contains('hidden');

  if (e.key === 'Escape') {
    if (fullscreenOpen) { closeFullscreen(); return; }
    if (!document.getElementById('settings-modal').classList.contains('hidden')) {
      closeSettingsModal(); return;
    }
    closePanel(); return;
  }

  if (isInput) return;

  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
    const dir = e.key === 'ArrowLeft' ? -1 : 1;
    // Fullscreen originals navigation
    if (fullscreenOpen && viewMode === 'originals' && originalsShots.length) {
      const next = originalsIndex + dir;
      if (next >= 0 && next < originalsShots.length) {
        originalsIndex = next;
        viewerRotation = 0;
        openOriginalFullscreen(originalsShots[originalsIndex]);
      }
      return;
    }
    // Edited photos panel navigation
    if (!currentFileKey) return;
    const idx = currentPhotos.findIndex(p => p.fileKey === currentFileKey);
    if (dir === -1 && idx > 0) openDetail(currentPhotos[idx - 1]);
    if (dir === 1 && idx < currentPhotos.length - 1) openDetail(currentPhotos[idx + 1]);
  }
  if ((e.key === 'e' || e.key === 'E') && currentFileKey) {
    document.getElementById('btn-ai').click();
  }
  if ((e.key === 's' || e.key === 'S') && currentFileKey) {
    document.getElementById('btn-save').click();
  }
  if ((e.key === 'r' || e.key === 'R') && fullscreenOpen) {
    rotateViewer(e.shiftKey ? -90 : 90);
  }
});

// ── Session rename ────────────────────────────────────────────────────────────
function startSessionRename(session, el) {
  const dateDiv = el.querySelector('.session-date');
  const currentLabel = session.label || '';

  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'session-rename-input';
  input.value = currentLabel;
  input.placeholder = 'Label (e.g. Belgrade)';

  dateDiv.replaceWith(input);
  input.focus();
  input.select();

  let committed = false;

  async function commit() {
    if (committed) return;
    committed = true;
    const newLabel = input.value.trim();
    try {
      const result = await api('POST', `/api/rename-session/${session.folderKey}`, { label: newLabel });
      const wasActive = currentSession && currentSession.folderKey === session.folderKey;
      await loadSessions();
      if (wasActive) {
        const newEl = document.querySelector(`.session-item[data-key="${result.folderKey}"]`);
        if (newEl) {
          const newKey = result.folderKey;
          const newSessions = await api('GET', '/api/sessions');
          const newSession = newSessions.find(s => s.folderKey === newKey);
          if (newSession && newEl) selectSession(newSession, newEl);
        }
      }
    } catch (err) {
      showToast(err.message, 'error');
      await loadSessions();
    }
  }

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); commit(); }
    if (e.key === 'Escape') { e.preventDefault(); committed = true; loadSessions(); }
  });
  input.addEventListener('blur', () => commit());
}

// ── Import modal ──────────────────────────────────────────────────────────────
document.getElementById('btn-import').onclick = openImportModal;
document.getElementById('btn-import-close').onclick = closeImportModal;
document.getElementById('btn-import-cancel').onclick = closeImportModal;

function openImportModal() {
  document.getElementById('import-modal').classList.remove('hidden');
  detectCards();
}

function closeImportModal() {
  document.getElementById('import-modal').classList.add('hidden');
}

async function detectCards() {
  const sel = document.getElementById('import-drive-select');
  sel.innerHTML = '<option>Detecting…</option>';
  const { drives } = await api('GET', '/api/import/drives');
  sel.innerHTML = '';
  if (!drives.length) {
    sel.innerHTML = '<option value="">No SD cards detected</option>';
    return;
  }
  for (const d of drives) {
    const opt = document.createElement('option');
    opt.value = d; opt.textContent = `${d} (DCIM found)`;
    sel.appendChild(opt);
  }
}

document.getElementById('btn-import-detect').onclick = detectCards;

document.getElementById('btn-import-preview').onclick = async () => {
  const drive = document.getElementById('import-drive-select').value;
  if (!drive) return;
  const btn = document.getElementById('btn-import-preview');
  btn.disabled = true; btn.textContent = 'Scanning…';
  try {
    const p = await api('GET', `/api/import/preview?drive=${encodeURIComponent(drive)}`);
    const info = document.getElementById('import-info');
    info.style.display = '';
    const dates = p.dates.length ? p.dates.join(', ') : '—';
    info.innerHTML = `
      <div style="margin-bottom:6px"><b>${p.newCount} new files</b> to import &nbsp;·&nbsp; ${p.existingCount} already imported &nbsp;·&nbsp; ${p.total} total</div>
      <div style="color:var(--text2);font-size:11px">Dates: ${dates}</div>`;
    document.getElementById('btn-import-start').disabled = p.newCount === 0;
  } finally {
    btn.disabled = false; btn.textContent = 'Preview';
  }
};

document.getElementById('btn-import-start').onclick = async () => {
  const drive = document.getElementById('import-drive-select').value;
  if (!drive) return;

  document.getElementById('btn-import-start').disabled = true;
  document.getElementById('btn-import-cancel').disabled = true;
  document.getElementById('import-progress-wrap').style.display = '';
  const log = document.getElementById('import-file-log');
  log.innerHTML = '';

  const res = await fetch('/api/import/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ drive })
  });

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const p = JSON.parse(line);
        if (p.type === 'progress') {
          const pct = Math.round((p.done / p.total) * 100);
          document.getElementById('import-progress-fill').style.width = pct + '%';
          document.getElementById('import-progress-count').textContent = `${p.done}/${p.total}`;
          document.getElementById('import-progress-label').textContent = p.file;
          const entry = document.createElement('div');
          entry.textContent = (p.skipped ? '⏭ skip: ' : '✓ ') + p.file;
          entry.style.color = p.skipped ? 'var(--border2)' : 'var(--text)';
          log.appendChild(entry);
          log.scrollTop = log.scrollHeight;
        } else if (p.type === 'done') {
          document.getElementById('import-progress-label').textContent = `Done! Copied ${p.copied} files, skipped ${p.skippedCount}.`;
          document.getElementById('import-progress-fill').style.width = '100%';
          document.getElementById('btn-import-cancel').disabled = false;
          document.getElementById('btn-import-cancel').textContent = 'Close';
          await loadSessions();
        }
      } catch {}
    }
  }
};

// ── Originals view ───────────────────────────────────────────────────────────
let viewMode = 'edited'; // 'edited' | 'originals'
let originalsShots = [];
let originalsIndex = -1;

function setViewMode(mode) {
  viewMode = mode;
  document.getElementById('btn-view-edited').classList.toggle('active', mode === 'edited');
  document.getElementById('btn-view-originals').classList.toggle('active', mode === 'originals');
  document.getElementById('btn-enrich-all').classList.toggle('hidden', mode === 'originals');
  document.getElementById('btn-select-all').classList.toggle('hidden', mode === 'originals');

  closePanel();
  clearSelection();
  originalsShots = [];
  originalsIndex = -1;

  if (!currentSession) return;
  if (mode === 'edited') {
    loadPhotos(currentSession.folderKey);
  } else {
    loadOriginals(currentSession.folderKey);
  }
}

async function loadOriginals(folderKey) {
  const gallery = document.getElementById('gallery');
  gallery.innerHTML = '<div class="empty-state"><div class="big">⏳</div><p>Loading…</p></div>';
  try {
    const shots = await api('GET', `/api/originals/${folderKey}`);
    originalsShots = shots;
    originalsIndex = -1;
    renderOriginalsGallery(shots);
  } catch (err) {
    gallery.innerHTML = `<div class="empty-state"><div class="big">⚠️</div><p>${escHtml(err.message)}</p></div>`;
  }
}

function renderOriginalsGallery(shots) {
  const gallery = document.getElementById('gallery');
  gallery.innerHTML = '';

  if (!shots.length) {
    gallery.innerHTML = '<div class="empty-state"><div class="big">📂</div><p>No original files found in JPEG/ or RAW/ folders</p></div>';
    return;
  }

  const bothCount = shots.filter(s => s.jpegKey && s.rawKey).length;
  const jpegOnly  = shots.filter(s => s.jpegKey && !s.rawKey).length;
  const rawOnly   = shots.filter(s => !s.jpegKey && s.rawKey).length;

  const info = document.createElement('div');
  info.style.cssText = 'column-span:all;color:var(--text2);font-size:11px;padding:0 2px 6px';
  const parts = [];
  if (bothCount) parts.push(`${bothCount} JPEG+RAW`);
  if (jpegOnly)  parts.push(`${jpegOnly} JPEG only`);
  if (rawOnly)   parts.push(`${rawOnly} RAW only`);
  info.textContent = `${shots.length} shots — ${parts.join(' · ')}`;
  gallery.appendChild(info);

  for (const shot of shots) {
    // Prefer JPEG for thumbnail (faster), fall back to RAW embedded preview
    const thumbKey  = shot.jpegKey ?? shot.rawKey;
    const thumbSrc  = `/api/image-raw/${thumbKey}?size=thumb`;
    const hasRaw    = !!shot.rawKey;
    const hasJpeg   = !!shot.jpegKey;
    const hasBoth   = hasRaw && hasJpeg;

    // Badge: show what formats are available
    const badgeText = hasBoth ? 'JPEG · RAW' : hasRaw ? 'RAW' : 'JPEG';
    const badgeCls  = hasRaw ? 'raw' : 'jpeg';
    const displayName = shot.jpegName ?? shot.rawName ?? shot.base;

    const card = document.createElement('div');
    card.className = `photo-card orig-card${hasRaw ? ' raw-card' : ''}`;
    card.dataset.base = shot.base;
    card.innerHTML = `
      <span class="orig-type-badge ${badgeCls}">${escHtml(badgeText)}</span>
      <img class="photo-thumb" src="${thumbSrc}" loading="lazy" alt="${escHtml(displayName)}"
           onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" />
      <div class="photo-thumb-missing" style="display:none">
        <span class="raw-icon">🎞</span><span>No preview</span>
      </div>
      <div class="photo-info">
        <div class="photo-name">${escHtml(shot.base)}</div>
      </div>`;

    card.addEventListener('click', () => {
      originalsIndex = originalsShots.indexOf(shot);
      openOriginalFullscreen(shot);
    });
    gallery.appendChild(card);
  }
}

async function openOriginalFullscreen(shot) {
  const previewKey = shot.jpegKey ?? shot.rawKey;
  const metaKey    = shot.jpegKey ?? shot.rawKey;
  const label = shot.jpegName ?? shot.rawName ?? shot.base;
  const formats = [shot.jpegKey ? 'JPEG' : null, shot.rawKey ? 'RAW' : null].filter(Boolean).join(' + ');
  const pos = originalsIndex >= 0 ? ` · ${originalsIndex + 1}/${originalsShots.length}` : '';

  document.getElementById('fullscreen-img').src = `/api/image-raw/${previewKey}?size=preview`;
  document.getElementById('fullscreen-caption').textContent = `${label}  ·  ${formats}${pos}`;
  document.getElementById('fullscreen-exif').classList.add('hidden');
  document.getElementById('fullscreen-overlay').classList.remove('hidden');

  // Load EXIF async — show overlay immediately, fill exif when ready
  try {
    const meta = await api('GET', `/api/meta/${metaKey}`);
    renderFullscreenExif(meta);
  } catch { /* no exif = no strip */ }
}

// ── Watch folder (SSE) ────────────────────────────────────────────────────────
function connectWatcher() {
  let sse;
  try {
    sse = new EventSource('/api/watch');
  } catch {
    return;
  }
  let lastReload = 0;
  sse.onmessage = (e) => {
    try {
      const data = JSON.parse(e.data);
      if (data.event === 'change') {
        const now = Date.now();
        if (now - lastReload > 5000) {
          lastReload = now;
          loadSessions();
          showToast('Session list updated — new photos detected');
        }
      }
    } catch {}
  };
  sse.onerror = () => {
    sse.close();
    setTimeout(connectWatcher, 15000);
  };
}

// ── Init ──────────────────────────────────────────────────────────────────────
checkStatus();
loadSessions();
connectWatcher();
