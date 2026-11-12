/* Photo Curator: single-page UI over the collection API (app/web/timeline_bp.py). */
'use strict';

/* ---------- language ---------- */
const STR = {
  en: {
    collection:'Collection', noCollections:'No collections', index:'Index photos', describe:'Describe with local AI',
    stopDescribe:'Stop describing', thumbSize:'Thumbnail size', searchPh:'Search photos, e.g. sunset, Firence',
    library:'Library', timeline:'Timeline', duplicates:'Duplicates', best:'Best photos', search:'Search results',
    export:'Export', sources:'Sources & clocks', settings:'Settings', photos:'Photos', organize:'Organize', setup:'Setup',
    all:'All', sharp:'Sharp', soft:'Soft', blurry:'Blurry', auto:'Auto', noPlace:'No GPS', withPlace:'With place',
    items:'items', photosN:'photos', emptyColl:'No collection yet', emptyCollHint:'Open Sources & clocks to create a collection and add one folder per person or device, then index it.',
    emptyIdx:'Nothing indexed yet', emptyIdxHint:'Add a source folder for each person or device in Sources & clocks, then choose Index photos.',
    noMatch:'No photos match these filters.', captureTime:'Capture time', confidence:'Time confidence', rule:'Rule',
    source:'Source', device:'Device', size:'Size', place:'Place', gps:'GPS', file:'File', none:'none',
    unknownNoGps:'unknown (no GPS)', fromGps:'from GPS', kmFrom:'km from the place centre', clockFix:'Clock fix',
    fileSays:'The file says', focus:'Focus', focusHint:'A mark only. Files never move.', wallpaper:'Phone wallpaper',
    excludeBest:'Leave out of Best photos', aiDesc:'AI description, not verified', textInPhoto:'Text in the photo',
    howTime:'How this time was decided', splitHere:'Start a new event at this photo', rename:'Rename',
    mergePrev:'Merge with previous', undoDay:'Undo my event edits for this day', eventName:'Event name',
    namedByYou:'named by you', identical:'Identical files', near:'Near duplicates', similar:'Similar scene, different shots',
    keep:'Keep', keepThis:'Keep this one', useRec:'Use the recommendation', dupKeys:'Keys: ↑ ↓ group, ← → photo, K keep',
    noDups:'No duplicate groups', noDupsHint:'Index photos to look for duplicates.',
    weights:'Ranking weights', topN:'How many', composition:'Composition', technical:'Technical', sharpness:'Sharpness',
    color:'Colour', aesthetic:'Overall look', resetWeights:'Reset', remove:'Remove', restore:'Restore',
    exportThese:'Export these', exportWall:'Export phone wallpapers', bestHint:'Ranked by the weighted score. Blurry photos and duplicates are left out. Keys: B wallpaper, X remove.',
    fileNames:'File names', folders:'Folders', dupsOpt:'Duplicates (not the kept photo)', selection:'Which photos',
    selAll:'All photos', selNoBlurry:'All except blurry', selBest:'Best photos only', preview:'Preview',
    chooseDest:'Choose destination and export', exportHint:'Exports copy the original files into a new folder you choose. Every copy is checked by checksum and listed in manifest.json with its original name. Your photo folders are never changed.',
    noPreview:'No preview yet', noPreviewHint:'Choose the options, then Preview.', files:'files', foldersN:'folders',
    newPath:'New path', original:'Original', showing:'Showing', of:'of', leaveOut:'Leave out',
    alternatives:'Put in Alternatives/, the rest in Selected/', includeToo:'Export them too',
    byDayPlace:'By day and place: 2026-10-28_Florence/', byDay:'By day: 2026-10-28/', byEvent:'By day and event: 2026-10-28/Florence, morning/',
    byPlace:'By place: Italy/Florence/', oneFolder:'One folder',
    newColl:'New collection, e.g. Tuscany 2026', create:'Create', owner:'Whose photos? e.g. Andraž', path:'Folder path (or Browse)',
    browse:'Browse', addSource:'Add source', readOnly:'Source folders are only read. Nothing is written into them.',
    files_:'files', clocks:'Device clocks', reference:'Reference: other devices are aligned to this clock.',
    rejected:'Suggestion rejected.', notAnalysed:'Not analysed yet. Index photos first.', apply:'Apply', set:'Set',
    undo:'Undo', reject:'Reject', seconds:'seconds', applied:'applied', clockHint:'A correction only changes the order and the shown time here. Files are never changed.',
    language:'Language', aiLimit:'How hard local AI may work', gentle:'Gentle: GPU busy about 25 % of the time',
    def30:'Default: about 30 %', faster:'Faster: about 50 %', noLimit:'No limit (the Mac gets warm)',
    pauseBattery:'Pause while on battery', aiModels:'Local AI', searchModel:'Search model', descModel:'Description model',
    ready:'ready', missing:'missing', running:'running', notRunning:'not running (starts when needed)', saved:'Saved.',
    keysTitle:'Keyboard', keysLib:'Arrows move, Space shows the photo large, 1 2 3 set Sharp / Soft / Blurry, 0 back to auto, B wallpaper, Esc closes.',
    searching:'Searching…', alsoAs:'also searched as', simGuess:'the order is a similarity guess, not a verified label',
    placeMatch:'place match', tagMatch:'tag match', bestOf:'best matches for', duplicate:'duplicate', exactCopy:'exact copy',
    paired:'paired', alternative:'alternative', chooseFolder:'Choose a destination folder in the dialog…', cancelled:'Cancelled.',
    exportStarted:'Export started.', undated:'No date', confText:{high:'Exact capture time',medium:'Time zone assumed',low:'Camera clock only, time zone unknown',unknown:'No capture time in the file'},
  },
  sl: {
    collection:'Zbirka', noCollections:'Ni zbirk', index:'Indeksiraj fotografije', describe:'Opiši z lokalnim AI',
    stopDescribe:'Ustavi opisovanje', thumbSize:'Velikost sličic', searchPh:'Išči, npr. sončni zahod, Firence',
    library:'Knjižnica', timeline:'Časovnica', duplicates:'Dvojniki', best:'Najboljše', search:'Rezultati iskanja',
    export:'Izvoz', sources:'Viri in ure', settings:'Nastavitve', photos:'Fotografije', organize:'Urejanje', setup:'Sistem',
    all:'Vse', sharp:'Ostre', soft:'Mehke', blurry:'Zamegljene', auto:'Samodejno', noPlace:'Brez GPS', withPlace:'S krajem',
    items:'elementov', photosN:'fotografij', emptyColl:'Ni še zbirke', emptyCollHint:'V »Viri in ure« ustvari zbirko, dodaj mapo za vsako osebo ali napravo in jo indeksiraj.',
    emptyIdx:'Nič še ni indeksirano', emptyIdxHint:'V »Viri in ure« dodaj mapo za vsako osebo ali napravo, nato izberi Indeksiraj fotografije.',
    noMatch:'Nobena fotografija ne ustreza filtrom.', captureTime:'Čas zajema', confidence:'Zanesljivost časa', rule:'Pravilo',
    source:'Vir', device:'Naprava', size:'Velikost', place:'Kraj', gps:'GPS', file:'Datoteka', none:'ni',
    unknownNoGps:'neznan (ni GPS)', fromGps:'iz GPS', kmFrom:'km od središča kraja', clockFix:'Popravek ure',
    fileSays:'V datoteki piše', focus:'Ostrina', focusHint:'Samo oznaka. Datoteke se nikoli ne premaknejo.', wallpaper:'Ozadje za telefon',
    excludeBest:'Izpusti iz Najboljših', aiDesc:'Opis AI, ni preverjen', textInPhoto:'Besedilo na fotografiji',
    howTime:'Kako je bil čas določen', splitHere:'Začni nov dogodek pri tej fotografiji', rename:'Preimenuj',
    mergePrev:'Združi s prejšnjim', undoDay:'Razveljavi moje popravke dogodkov za ta dan', eventName:'Ime dogodka',
    namedByYou:'poimenoval ti', identical:'Enake datoteke', near:'Skoraj enaki posnetki', similar:'Podoben prizor, različni posnetki',
    keep:'Obdrži', keepThis:'Obdrži tega', useRec:'Uporabi priporočilo', dupKeys:'Tipke: ↑ ↓ skupina, ← → fotografija, K obdrži',
    noDups:'Ni skupin dvojnikov', noDupsHint:'Indeksiraj fotografije, da poiščem dvojnike.',
    weights:'Uteži razvrščanja', topN:'Koliko', composition:'Kompozicija', technical:'Tehnika', sharpness:'Ostrina',
    color:'Barve', aesthetic:'Skupni vtis', resetWeights:'Ponastavi', remove:'Odstrani', restore:'Vrni',
    exportThese:'Izvozi te', exportWall:'Izvozi ozadja za telefon', bestHint:'Razvrščeno po uteženi oceni. Zamegljene in dvojniki so izpuščeni. Tipki: B ozadje, X odstrani.',
    fileNames:'Imena datotek', folders:'Mape', dupsOpt:'Dvojniki (razen obdržanega)', selection:'Katere fotografije',
    selAll:'Vse fotografije', selNoBlurry:'Vse razen zamegljenih', selBest:'Samo najboljše', preview:'Predogled',
    chooseDest:'Izberi cilj in izvozi', exportHint:'Izvoz kopira izvirne datoteke v novo mapo, ki jo izbereš. Vsaka kopija se preveri s kontrolno vsoto in zapiše v manifest.json z izvirnim imenom. Tvoje mape s fotografijami se nikoli ne spremenijo.',
    noPreview:'Ni še predogleda', noPreviewHint:'Izberi možnosti, nato Predogled.', files:'datotek', foldersN:'map',
    newPath:'Nova pot', original:'Izvirnik', showing:'Prikazanih', of:'od', leaveOut:'Izpusti',
    alternatives:'V Alternatives/, ostalo v Selected/', includeToo:'Izvozi tudi njih',
    byDayPlace:'Po dnevu in kraju: 2026-10-28_Florence/', byDay:'Po dnevu: 2026-10-28/', byEvent:'Po dnevu in dogodku: 2026-10-28/Florence, morning/',
    byPlace:'Po kraju: Italy/Florence/', oneFolder:'Ena mapa',
    newColl:'Nova zbirka, npr. Toskana 2026', create:'Ustvari', owner:'Čigave fotografije? npr. Andraž', path:'Pot do mape (ali Prebrskaj)',
    browse:'Prebrskaj', addSource:'Dodaj vir', readOnly:'Mape virov se samo berejo. Vanje se nič ne zapiše.',
    files_:'datotek', clocks:'Ure naprav', reference:'Referenca: druge naprave so poravnane na to uro.',
    rejected:'Predlog zavrnjen.', notAnalysed:'Še ni analizirano. Najprej indeksiraj fotografije.', apply:'Uporabi', set:'Nastavi',
    undo:'Razveljavi', reject:'Zavrni', seconds:'sekunde', applied:'uporabljeno', clockHint:'Popravek spremeni samo vrstni red in prikazani čas tukaj. Datoteke se nikoli ne spremenijo.',
    language:'Jezik', aiLimit:'Kako močno sme delati lokalni AI', gentle:'Nežno: GPU zaseden okoli 25 % časa',
    def30:'Privzeto: okoli 30 %', faster:'Hitreje: okoli 50 %', noLimit:'Brez omejitve (Mac se segreje)',
    pauseBattery:'Premor na bateriji', aiModels:'Lokalni AI', searchModel:'Model za iskanje', descModel:'Model za opise',
    ready:'pripravljen', missing:'manjka', running:'teče', notRunning:'ne teče (zažene se po potrebi)', saved:'Shranjeno.',
    keysTitle:'Tipkovnica', keysLib:'Puščice premikajo, presledek pokaže fotografijo veliko, 1 2 3 nastavi Ostra / Mehka / Zamegljena, 0 nazaj na samodejno, B ozadje, Esc zapre.',
    searching:'Iščem…', alsoAs:'iskano tudi kot', simGuess:'vrstni red je ocena podobnosti, ne preverjena oznaka',
    placeMatch:'ujemanje kraja', tagMatch:'ujemanje oznake', bestOf:'najboljših zadetkov za', duplicate:'dvojnik', exactCopy:'enaka kopija',
    paired:'par', alternative:'alternativa', chooseFolder:'Izberi ciljno mapo v oknu…', cancelled:'Preklicano.',
    exportStarted:'Izvoz se je začel.', undated:'Brez datuma', confText:{high:'Natančen čas zajema',medium:'Časovni pas predpostavljen',low:'Samo ura naprave, časovni pas neznan',unknown:'Datoteka nima časa zajema'},
  },
};
let lang = 'en';
const t = k => (STR[lang] && STR[lang][k]) ?? STR.en[k] ?? k;
/* Warnings come from the server in English; translate the known ones. */
const WARN_SL = {'duplicates skipped': 'dvojnikov izpuščenih', 'no place (no GPS)': 'brez kraja (ni GPS)',
  'no trustworthy capture time': 'brez zanesljivega časa zajema', 'paired files kept together': 'parov ohranjenih skupaj'};
const tw = k => lang === 'sl' ? (WARN_SL[k] || k.replace(/^left out by selection \((.*)\)$/, 'izpuščenih zaradi izbire ($1)')) : k;

/* ---------- helpers ---------- */
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const api = (url, opt = {}) => fetch(url, {headers: {'Content-Type': 'application/json'}, ...opt}).then(r => r.json());
const post = (url, body) => api(url, {method: 'POST', body: JSON.stringify(body || {})});
const thumb = p => `/api/thumb?path=${encodeURIComponent(p)}&v=2`;
const LANES = ['#0d9488', '#d97706', '#7c3aed', '#e11d48', '#0284c7', '#65a30d'];
const S = {cid: null, data: null, dups: [], clocks: [], settings: {}, view: 'library', sel: -1, list: [],
           filter: {focus: 'all', source: 'all', place: 'all'}, searchRes: null, best: null,
           exportOpts: {template: 'default', folders: 'day', duplicates: 'skip', selection: 'all', topn: 50},
           plan: null, dupG: 0, dupC: 0, polling: null};
const lane = sid => { const i = (S.data?.sources || []).findIndex(s => s.id === sid); return LANES[(i < 0 ? 0 : i) % LANES.length]; };
function status(msg, bad) { $('#status').textContent = msg || ''; $('#status').classList.toggle('bad', !!bad); }
function local(it) {
  const lt = it.corrected_local_time || it.local_time, ut = it.corrected_utc_time || it.utc_time;
  if (lt) { const [d, tm] = lt.split('T'); return {day: d, time: tm.slice(0, 8)}; }
  if (ut) { const [d, tm] = ut.replace('Z', '').split('T'); return {day: d, time: tm.slice(0, 8)}; }
  return {day: 'unknown', time: '?'};
}
const dayTitle = d => d === 'unknown' ? t('undated') :
  new Date(d + 'T12:00:00').toLocaleDateString(lang === 'sl' ? 'sl-SI' : 'en-GB', {weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'});
const fmtSec = s => (s > 0 ? '+' : '') + (Math.abs(s) >= 90 ? Math.round(s / 6) / 10 + ' min' : Math.round(s * 10) / 10 + ' s');
const fmtOffset = m => m == null ? '' : `${m < 0 ? '-' : '+'}${String(Math.abs(m) / 60 | 0).padStart(2, '0')}:${String(Math.abs(m) % 60).padStart(2, '0')}`;

/* ---------- loading ---------- */
async function boot() {
  const st = await api('/api/settings'); S.settings = st.settings || {}; lang = S.settings.ui_language || 'en';
  document.documentElement.lang = lang;
  applyStatic();
  try { S.view = localStorage.getItem('pc-view') || 'library'; $('#zoom').value = localStorage.getItem('pc-zoom') || 160; } catch (e) {}
  setZoom();
  await loadCollections();
}
function applyStatic() {
  document.querySelectorAll('[data-t]').forEach(el => el.textContent = t(el.dataset.t));
  document.querySelectorAll('[data-tp]').forEach(el => el.placeholder = t(el.dataset.tp));
}
async function loadCollections(select) {
  const d = await api('/api/collections'); const list = d.collections || [];
  $('#coll').innerHTML = list.length ? list.map(c => `<option value="${esc(c.id)}">${esc(c.name)} (${c.assets})</option>`).join('')
                                     : `<option value="">${esc(t('noCollections'))}</option>`;
  let want = select; try { want = want || localStorage.getItem('pc-coll'); } catch (e) {}
  if (want && list.some(c => c.id === want)) $('#coll').value = want;
  S.cid = $('#coll').value || null;
  await reload();
  checkJob();
}
$('#coll').onchange = () => { S.cid = $('#coll').value; try { localStorage.setItem('pc-coll', S.cid); } catch (e) {} S.sel = -1; S.searchRes = null; S.plan = null; reload(); };
async function reload() {
  if (!S.cid) { S.data = null; render(); return; }
  const [data, dups, clocks, sources] = await Promise.all([
    api(`/api/collections/${S.cid}/timeline`), api(`/api/collections/${S.cid}/duplicates`),
    api(`/api/collections/${S.cid}/clocks`), api(`/api/collections/${S.cid}/sources`)]);
  S.data = data; S.data.sources = sources.sources || []; S.dups = dups.groups || []; S.clocks = clocks.clocks || [];
  render();
}

/* ---------- navigation ---------- */
const VIEWS = [['photos', ['library', 'timeline', 'best']], ['organize', ['duplicates', 'search', 'export']], ['setup', ['sources', 'settings']]];
function counts() {
  const items = S.data?.items || [];
  return {library: items.length, timeline: (S.data?.events || []).length,
          duplicates: S.dups.filter(g => g.category !== 'similar_scene').length,
          search: S.searchRes ? (S.searchRes.results || []).length : null};
}
function renderNav() {
  const c = counts();
  $('#nav').innerHTML = VIEWS.map(([sec, vs]) => `<div class="sec">${esc(t(sec))}</div>` + vs.filter(v => v !== 'search' || S.searchRes)
    .map(v => `<button data-v="${v}" ${S.view === v ? 'aria-current="page"' : ''}><span>${esc(t(v))}</span>${c[v] != null ? `<small>${c[v]}</small>` : ''}</button>`).join('')).join('');
  document.querySelectorAll('#nav [data-v]').forEach(b => b.onclick = () => go(b.dataset.v));
}
function go(v) { S.view = v; S.sel = -1; try { localStorage.setItem('pc-view', v); } catch (e) {} closeInspector(); render(); $('#main').focus(); }
function render() {
  renderNav();
  $('#title').textContent = t(S.view);
  $('#tools').innerHTML = '';
  const m = $('#main');
  if (!S.cid && !['sources', 'settings'].includes(S.view)) { m.innerHTML = empty('emptyColl', 'emptyCollHint'); return; }
  if (S.cid && !(S.data?.items || []).length && !['sources', 'settings'].includes(S.view)) { m.innerHTML = empty('emptyIdx', 'emptyIdxHint'); return; }
  ({library: viewLibrary, timeline: viewTimeline, duplicates: viewDuplicates, best: viewBest, search: viewSearch,
    export: viewExport, sources: viewSources, settings: viewSettings}[S.view] || viewLibrary)();
}
const empty = (a, b) => `<div class="empty"><strong>${esc(t(a))}</strong>${esc(t(b))}</div>`;

/* ---------- tiles ---------- */
function tile(it, idx, extra = '') {
  const p = local(it);
  const b = [];
  if (it.focus && it.focus.tier !== 'sharp') b.push(`<span class="badge ${it.focus.tier}">${esc(t(it.focus.tier))}</span>`);
  if (it.duplicate && it.duplicate.category !== 'similar_scene' && it.duplicate.keeper === false) b.push(`<span class="badge">${esc(t('duplicate'))}</span>`);
  if (it.wallpaper) b.push('<span class="badge">▯</span>');
  const img = it.kind === 'image' ? `<img loading="lazy" alt="" src="${thumb(it.path)}">` : `<span class="vid">${esc(it.ext)}</span>`;
  return `<button class="tile ${it.excluded ? 'dim' : ''}" data-i="${idx}" aria-selected="${S.sel === idx}" title="${esc(it.filename)}">${img}
    <span class="badges">${b.join('')}${extra}</span><span class="cap"><span>${esc(p.time.slice(0, 5))}</span><span>${esc(it.owner)}</span></span>
    <span class="lane" style="background:${lane(it.source_id)}"></span></button>`;
}
function bindTiles() {
  document.querySelectorAll('#main .tile[data-i]').forEach(el => {
    el.onclick = () => select(+el.dataset.i);
    el.ondblclick = () => quickLook();
  });
}
function select(i) {
  if (i < 0 || i >= S.list.length) return;
  S.sel = i;
  document.querySelectorAll('#main .tile[aria-selected=true]').forEach(e => e.setAttribute('aria-selected', 'false'));
  const el = document.querySelector(`#main .tile[data-i="${i}"]`);
  if (el) { el.setAttribute('aria-selected', 'true'); el.focus({preventScroll: true}); el.scrollIntoView({block: 'nearest'}); }
  inspector(S.list[i]);
}

/* ---------- library ---------- */
function viewLibrary() {
  const f = S.filter, items = S.data.items;
  const srcs = S.data.sources || [];
  const chips = (key, opts) => opts.map(([v, label]) => `<button class="chip" data-f="${key}" data-val="${v}" aria-pressed="${f[key] === v}">${label}</button>`).join('');
  $('#tools').innerHTML = chips('focus', [['all', esc(t('all'))], ['sharp', esc(t('sharp'))], ['soft', esc(t('soft'))], ['blurry', esc(t('blurry'))]])
    + `<span class="gap"></span>` + chips('source', [['all', esc(t('all'))], ...srcs.map(s => [String(s.id), `<span class="dot" style="background:${lane(s.id)}"></span>${esc(s.owner)}`])])
    + `<span class="gap"></span>` + chips('place', [['all', esc(t('all'))], ['yes', esc(t('withPlace'))], ['no', esc(t('noPlace'))]]);
  document.querySelectorAll('[data-f]').forEach(b => b.onclick = () => { S.filter[b.dataset.f] = b.dataset.val; S.sel = -1; closeInspector(); render(); });
  S.list = items.filter(it => (f.focus === 'all' || it.focus?.tier === f.focus)
    && (f.source === 'all' || String(it.source_id) === f.source)
    && (f.place === 'all' || (f.place === 'yes') === !!it.place));
  $('#main').innerHTML = S.list.length ? `<p class="hint" style="margin:0 0 10px">${S.list.length} ${esc(t('photosN'))}. ${esc(t('keysLib'))}</p><div class="grid">${S.list.map((it, i) => tile(it, i)).join('')}</div>`
                                       : `<div class="empty">${esc(t('noMatch'))}</div>`;
  bindTiles();
  if (S.sel >= 0) select(S.sel);
}

/* ---------- timeline ---------- */
function viewTimeline() {
  const items = S.data.items, evs = {}; (S.data.events || []).forEach(e => evs[e.id] = e);
  S.list = items;
  let html = '', day = null, ev, first = true;
  items.forEach((it, idx) => {
    const p = local(it);
    if (p.day !== day) {
      if (day !== null) html += '</div></div></section>';
      day = p.day; ev = undefined; first = true;
      const n = items.filter(x => local(x).day === day).length;
      const edited = (S.data.events || []).some(e => e.day === day && e.locked);
      html += `<section class="day"><h2>${esc(dayTitle(day))}<small>${n} ${esc(t('items'))}</small>${edited ? `<button class="link" data-reset="${esc(day)}">${esc(t('undoDay'))}</button>` : ''}</h2><div>`;
    }
    if (it.event_id !== ev) {
      if (ev !== undefined) html += '</div></div>';
      ev = it.event_id; const E = evs[ev] || {name: '', count: 0};
      html += `<div class="event"><header><b>${esc(E.name)}</b><time>${esc(p.time.slice(0, 5))}</time><span class="hint">${E.count} ${esc(t('photosN'))}${E.name_source === 'user' ? ', ' + esc(t('namedByYou')) : ''}</span>
        ${E.id ? `<button class="link" data-ren="${E.id}">${esc(t('rename'))}</button>` : ''}${E.id && !first ? `<button class="link" data-merge="${E.id}">${esc(t('mergePrev'))}</button>` : ''}</header><div class="grid">`;
      first = false;
    }
    html += tile(it, idx);
  });
  html += '</div></div></div></section>';
  $('#main').innerHTML = html;
  bindTiles();
  document.querySelectorAll('[data-ren]').forEach(b => b.onclick = async () => {
    const cur = evs[+b.dataset.ren]; const name = prompt(t('eventName'), cur ? cur.name : ''); if (!name) return;
    eventAction(`/events/${b.dataset.ren}`, {action: 'rename', name}); });
  document.querySelectorAll('[data-merge]').forEach(b => b.onclick = () => eventAction(`/events/${b.dataset.merge}`, {action: 'merge_previous'}));
  document.querySelectorAll('[data-reset]').forEach(b => b.onclick = () => eventAction('/events/reset', {day: b.dataset.reset}));
  if (S.sel >= 0) select(S.sel);
}
async function eventAction(path, body) {
  const r = await post(`/api/collections/${S.cid}${path}`, body);
  if (r.error) { status(r.error, true); return; } status(''); await reload();
}

/* ---------- inspector ---------- */
function closeInspector() { $('#inspector').hidden = true; }
function inspector(it) {
  if (!it) return closeInspector();
  const p = local(it), I = $('#inspector'); I.hidden = false;
  const conf = it.confidence || 'unknown', f = it.focus;
  const seg = (k, v, label) => `<button data-focus="${v}" aria-pressed="${(f?.override || null) === v}">${esc(label)}</button>`;
  I.innerHTML = `${it.kind === 'image' ? `<img class="preview" alt="" src="${thumb(it.path)}" data-ql>` : ''}
    <h3>${esc(it.filename)}</h3>
    <dl>
      <dt>${esc(t('captureTime'))}</dt><dd>${esc(p.day)} ${esc(p.time)} ${it.offset_minutes != null ? esc(fmtOffset(it.offset_minutes)) : ''}</dd>
      <dt>${esc(t('confidence'))}</dt><dd><span class="pill ${esc(conf)}">${esc(conf)}</span> ${esc(t('confText')[conf] || '')}</dd>
      ${it.clock_correction_s ? `<dt>${esc(t('clockFix'))}</dt><dd>${esc(fmtSec(it.clock_correction_s))}. ${esc(t('fileSays'))} ${esc((it.local_time || '').replace('T', ' ').slice(0, 19))}</dd>` : ''}
      <dt>${esc(t('place'))}</dt><dd>${it.place ? `${esc(it.place.label)}${it.place.region ? ', ' + esc(it.place.region) : ''}${it.place.country ? ', ' + esc(it.place.country) : ''}<br><span class="hint">${esc(t('fromGps'))}, ${esc(it.place.distance_km)} ${esc(t('kmFrom'))}</span>` : esc(t('unknownNoGps'))}</dd>
      <dt>${esc(t('source'))}</dt><dd>${esc(it.owner)}</dd>
      <dt>${esc(t('device'))}</dt><dd>${esc(it.device)}</dd>
      <dt>${esc(t('size'))}</dt><dd>${it.width && it.height ? esc(it.width + ' × ' + it.height) : '?'}</dd>
      <dt>${esc(t('file'))}</dt><dd class="hint">${esc(it.path)}</dd>
    </dl>
    ${f ? `<section><b>${esc(t('focus'))}</b> <span class="pill ${esc(f.tier)}">${esc(t(f.tier))}</span>
      <div class="row"><span class="seg">${seg('focus', null, t('auto'))}${seg('focus', 'sharp', t('sharp'))}${seg('focus', 'soft', t('soft'))}${seg('focus', 'blurry', t('blurry'))}</span></div>
      <p class="hint">${esc(t('focusHint'))}</p></section>` : ''}
    <section><label class="hint" style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="wpBox" ${it.wallpaper ? 'checked' : ''}> ${esc(t('wallpaper'))}</label>
      <label class="hint" style="display:flex;gap:6px;align-items:center;margin-top:4px"><input type="checkbox" id="exBox" ${it.excluded ? 'checked' : ''}> ${esc(t('excludeBest'))}</label>
      ${it.event_id ? `<div class="row"><button class="btn small" id="splitBtn">${esc(t('splitHere'))}</button></div>` : ''}</section>
    ${it.ai ? `<section><div class="hint">${esc(t('aiDesc'))} (${esc(it.ai.model)})</div><p style="margin:4px 0">${esc(it.ai.description || '')}</p>
      <div class="row">${(it.ai.tags || []).map(x => `<span class="chip static">${esc(x)}</span>`).join('')}</div>
      ${it.ai.text_visible ? `<p class="hint">${esc(t('textInPhoto'))}: ${esc(it.ai.text_visible)}</p>` : ''}</section>` : ''}
    ${it.notes?.length ? `<section><div class="hint">${esc(t('howTime'))}</div><ul style="margin:4px 0;padding-left:18px;font-size:12px">${it.notes.map(n => `<li>${esc(n)}</li>`).join('')}</ul></section>` : ''}`;
  I.querySelectorAll('[data-focus]').forEach(b => b.onclick = () => mark(it, {focus: b.dataset.focus || null}));
  I.querySelector('#wpBox').onchange = e => mark(it, {wallpaper: e.target.checked});
  I.querySelector('#exBox').onchange = e => mark(it, {excluded: e.target.checked});
  const sp = I.querySelector('#splitBtn'); if (sp) sp.onclick = () => eventAction('/events/split', {asset_id: it.id});
  const pv = I.querySelector('[data-ql]'); if (pv) pv.onclick = quickLook;
}
async function mark(it, fields) {
  const r = await post(`/api/collections/${S.cid}/marks`, {asset_id: it.id, ...fields});
  if (r.error) { status(r.error, true); return; }
  const keep = S.sel; await reload(); if (keep >= 0) select(Math.min(keep, S.list.length - 1));
}

/* ---------- quick look ---------- */
function quickLook() {
  const it = S.list[S.sel]; if (!it || it.kind !== 'image') return;
  const q = $('#quicklook'); q.hidden = false;
  q.querySelector('img').src = `/api/image?path=${encodeURIComponent(it.path)}`;
  q.querySelector('.qlbar').textContent = `${it.filename} · ${local(it).day} ${local(it).time} · ← → · Esc`;
}
const closeQL = () => { $('#quicklook').hidden = true; $('#quicklook img').src = ''; };
$('#quicklook').onclick = closeQL;

/* ---------- duplicates ---------- */
function viewDuplicates() {
  const groups = S.dups;
  if (!groups.length) { $('#main').innerHTML = empty('noDups', 'noDupsHint'); return; }
  S.dupG = Math.min(S.dupG, groups.length - 1);
  const title = {exact: t('identical'), near: t('near'), similar_scene: t('similar')};
  $('#tools').innerHTML = `<span class="hint">${esc(t('dupKeys'))}</span>`;
  $('#main').innerHTML = groups.map((g, gi) => `<div class="group ${gi === S.dupG ? 'current' : ''}" data-g="${gi}">
    <h3>${esc(title[g.category] || g.category)}, ${g.members.length} ${esc(t('photosN'))}</h3>
    <div class="why">${esc((g.reasons.keeper || []).map(r => r.charAt(0).toUpperCase() + r.slice(1)).join('. '))}.</div>
    <div class="cands">${g.members.map((m, mi) => `<div class="cand ${m.id === g.keeper_id ? 'keep' : ''} ${gi === S.dupG && mi === S.dupC ? 'focus' : ''}" data-gi="${gi}" data-mi="${mi}">
      <img loading="lazy" alt="" src="${thumb(m.path)}"><div><b>${m.id === g.keeper_id ? esc(t('keep')) + ' · ' : ''}</b>${esc(m.filename)}</div>
      <div class="hint">${esc(m.owner)}, ${esc((m.local_time || '').slice(11, 19))}, ${m.width && m.height ? esc(m.width + '×' + m.height) : ''}, ${esc(t('sharpness').toLowerCase())} ${m.sharpness != null ? m.sharpness.toFixed(1) : '?'}</div>
      ${g.category !== 'similar_scene' && m.id !== g.keeper_id ? `<button class="btn small" data-keep="${gi}:${m.id}" style="margin:6px 8px 0">${esc(t('keepThis'))}</button>` : ''}</div>`).join('')}</div>
    ${g.category !== 'similar_scene' && (g.reasons.keeper || [])[0] === 'chosen by you' ? `<button class="link" data-keep="${gi}:" style="margin-top:8px">${esc(t('useRec'))}</button>` : ''}</div>`).join('');
  document.querySelectorAll('[data-keep]').forEach(b => b.onclick = e => { e.stopPropagation(); const [gi, id] = b.dataset.keep.split(':'); keeper(+gi, id ? +id : null); });
  document.querySelectorAll('.cand').forEach(c => c.onclick = () => { S.dupG = +c.dataset.gi; S.dupC = +c.dataset.mi; viewDuplicates(); });
  const cur = document.querySelector('.group.current'); if (cur) cur.scrollIntoView({block: 'nearest'});
}
async function keeper(gi, assetId) {
  await post(`/api/collections/${S.cid}/duplicates/${S.dups[gi].id}/keeper`, {asset_id: assetId});
  await reload();
}

/* ---------- best photos ---------- */
const CATS = ['aesthetic', 'composition', 'technical', 'sharpness', 'color'];
async function viewBest() {
  const topn = S.exportOpts.topn;
  const d = await api(`/api/collections/${S.cid}/best?topn=${topn}`);
  S.best = d; const w = d.weights;
  S.list = (d.photos || []).map(b => ({...S.data.items.find(i => i.id === b.id), rank: b.rank, score: b.score, scores: b.scores}));
  $('#tools').innerHTML = `<button class="btn small" id="toExport">${esc(t('exportThese'))}</button><button class="btn small" id="wpExport">${esc(t('exportWall'))}</button>`;
  $('#main').innerHTML = `<div class="card"><h3>${esc(t('weights'))}</h3><div class="weights">${CATS.map(c => `<label for="w-${c}">${esc(t(c))}</label>
      <input type="range" id="w-${c}" min="0" max="50" value="${w[c]}"><span id="wv-${c}">${w[c]}</span>`).join('')}
      <label for="topn">${esc(t('topN'))}</label><input type="number" id="topn" min="1" max="1000" value="${topn}" style="width:90px"><button class="link" id="resetW">${esc(t('resetWeights'))}</button></div>
      <p class="hint">${esc(t('bestHint'))}</p></div>
    <div class="grid">${S.list.map((it, i) => tile(it, i, `<span class="badge">#${it.rank} · ${it.score}</span>`)).join('')}</div>`;
  bindTiles();
  CATS.forEach(c => { const el = $(`#w-${c}`); el.oninput = () => $(`#wv-${c}`).textContent = el.value; el.onchange = saveWeights; });
  $('#topn').onchange = () => { S.exportOpts.topn = Math.max(1, +$('#topn').value || 50); viewBest(); };
  $('#resetW').onclick = async () => { await post('/api/settings', {rank_weights: {aesthetic: 30, composition: 22, technical: 20, sharpness: 16, color: 12}}); viewBest(); };
  $('#toExport').onclick = () => { S.exportOpts.selection = 'best'; S.plan = null; go('export'); };
  $('#wpExport').onclick = async () => { status(t('chooseFolder')); const r = await post(`/api/collections/${S.cid}/export/wallpapers`, {});
    if (r.cancelled) return status(t('cancelled')); if (r.error) return status(r.error, true); checkJob(); };
  if (S.sel >= 0) select(S.sel);
}
async function saveWeights() {
  const w = {}; CATS.forEach(c => w[c] = +$(`#w-${c}`).value);
  await post('/api/settings', {rank_weights: w}); viewBest();
}
function bestInspectorExtra(it) {
  if (!it.scores) return '';
  return `<section><div class="bars">${CATS.map(c => `<span>${esc(t(c))}</span><span class="track"><i style="width:${it.scores[c]}%"></i></span><span>${it.scores[c]}</span>`).join('')}</div></section>`;
}

/* ---------- search ---------- */
$('#searchForm').onsubmit = async e => {
  e.preventDefault(); const q = $('#q').value.trim(); if (!q || !S.cid) return;
  status(t('searching'));
  S.searchRes = await api(`/api/collections/${S.cid}/search?q=${encodeURIComponent(q)}`);
  status(S.searchRes.error || '', !!S.searchRes.error); go('search');
};
function viewSearch() {
  const r = S.searchRes || {}; if (r.error) { $('#main').innerHTML = `<div class="empty">${esc(r.error)}</div>`; return; }
  const res = r.results || [];
  S.list = res.map(x => S.data.items.find(i => i.id === x.id)).filter(Boolean);
  $('#main').innerHTML = `<p class="hint" style="margin:0 0 10px">${res.length} ${esc(t('bestOf'))} “${esc(r.query)}”${r.english ? `, ${esc(t('alsoAs'))} “${esc(r.english)}”` : ''}. ${esc(t('simGuess'))}.</p>
    <div class="grid">${S.list.map((it, i) => tile(it, i, res[i].place_match ? `<span class="badge">${esc(t('placeMatch'))}</span>` : res[i].tag_match ? `<span class="badge">${esc(t('tagMatch'))}</span>` : '')).join('')}</div>`;
  bindTiles();
}

/* ---------- export ---------- */
function sel(id, label, opts, cur) {
  return `<div><label for="${id}">${esc(label)}</label><select id="${id}">${opts.map(([v, x]) => `<option value="${v}" ${v === cur ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select></div>`;
}
function viewExport() {
  const o = S.exportOpts, p = S.plan;
  let html = `<div class="form">
    ${sel('xSel', t('selection'), [['all', t('selAll')], ['no_blurry', t('selNoBlurry')], ['best', t('selBest') + ` (${o.topn})`]], o.selection)}
    ${sel('xTemplate', t('fileNames'), [['default', '2026-10-28_11-02-02_Florence_morning_001.HEIC'], ['original', '20261028_110202_IMG_0581.HEIC'], ['place', '2026-10-28_Florence_001.HEIC'], ['trip', 'Trip_Day-6_Florence-morning_001.HEIC']], o.template)}
    ${sel('xFolders', t('folders'), [['day', t('byDayPlace')], ['date', t('byDay')], ['event', t('byEvent')], ['place', t('byPlace')], ['flat', t('oneFolder')]], o.folders)}
    ${sel('xDups', t('dupsOpt'), [['skip', t('leaveOut')], ['alternatives', t('alternatives')], ['include', t('includeToo')]], o.duplicates)}
    <div class="full" style="display:flex;gap:8px"><button class="btn" id="xPreview">${esc(t('preview'))}</button><button class="btn primary" id="xRun" ${p ? '' : 'disabled'}>${esc(t('chooseDest'))}</button></div>
    <p class="hint full" style="margin:0">${esc(t('exportHint'))}</p></div>`;
  if (!p) html += empty('noPreview', 'noPreviewHint');
  else html += `<p style="margin:14px 0 6px"><b>${p.files} ${esc(t('files'))}</b>, ${(p.bytes / 1e6).toFixed(0)} MB, ${p.folders_count} ${esc(t('foldersN'))}</p>
    <div class="row" style="display:flex;gap:6px;flex-wrap:wrap">${Object.entries(p.warnings || {}).map(([k, n]) => `<span class="chip static">${n} ${esc(tw(k))}</span>`).join('')}</div>
    <table class="plan"><thead><tr><th>${esc(t('newPath'))}</th><th>${esc(t('original'))}</th></tr></thead><tbody>${p.entries.slice(0, 300).map(e => `<tr><td>${esc(e.dest)}</td><td class="hint">${esc(e.original_name)}${e.paired_with ? ' (' + esc(t('paired')) + ')' : ''}${e.alternative ? ' (' + esc(t('alternative')) + ')' : ''}</td></tr>`).join('')}</tbody></table>
    ${p.entries.length > 300 ? `<p class="hint">${esc(t('showing'))} 300 ${esc(t('of'))} ${p.entries.length}.</p>` : ''}`;
  $('#main').innerHTML = html;
  const read = () => Object.assign(S.exportOpts, {selection: $('#xSel').value, template: $('#xTemplate').value, folders: $('#xFolders').value, duplicates: $('#xDups').value});
  ['xSel', 'xTemplate', 'xFolders', 'xDups'].forEach(id => $('#' + id).onchange = () => { read(); S.plan = null; viewExport(); });
  $('#xPreview').onclick = async () => { read(); const r = await post(`/api/collections/${S.cid}/export/preview`, S.exportOpts);
    if (r.error) return status(r.error, true); S.plan = r; viewExport(); };
  $('#xRun').onclick = async () => { read(); status(t('chooseFolder')); const r = await post(`/api/collections/${S.cid}/export`, S.exportOpts);
    if (r.cancelled) return status(t('cancelled')); if (r.error) return status(r.error, true); status(t('exportStarted')); checkJob(); };
}

/* ---------- sources & clocks ---------- */
function viewSources() {
  const srcs = S.data?.sources || [];
  let html = `<div class="card"><h3>${esc(t('collection'))}</h3><div class="form"><div><input type="text" id="newName" placeholder="${esc(t('newColl'))}"></div>
    <div><button class="btn" id="createBtn">${esc(t('create'))}</button></div></div></div>`;
  if (S.cid) {
    html += `<div class="card"><h3>${esc(t('sources'))}</h3>${srcs.map(s => `<div style="display:grid;grid-template-columns:12px 1fr auto;gap:2px 10px;align-items:center;padding:6px 0;border-bottom:1px solid var(--line)">
      <span class="dot" style="background:${lane(s.id)}"></span><input type="text" value="${esc(s.owner)}" data-owner="${s.id}" style="border:1px solid transparent;background:transparent;font-weight:600;padding:2px 4px;border-radius:5px">
      <span class="hint">${s.assets} ${esc(t('files_'))}</span><span></span><span class="hint" style="grid-column:2/4">${esc(s.path)}</span></div>`).join('')}
      <div class="form" style="margin-top:10px"><div><input type="text" id="owner" placeholder="${esc(t('owner'))}"></div><div><input type="text" id="path" placeholder="${esc(t('path'))}"></div>
      <div style="display:flex;gap:6px"><button class="btn" id="browseBtn">${esc(t('browse'))}</button><button class="btn" id="addBtn">${esc(t('addSource'))}</button></div></div>
      <p class="hint">${esc(t('readOnly'))}</p></div>`;
    html += `<div class="card"><h3>${esc(t('clocks'))}</h3>${S.clocks.map(c => {
      const e = c.evidence || {}, sug = c.suggested_s != null && !['accepted', 'manual'].includes(c.status);
      const note = c.status === 'reference' ? t('reference') : c.status === 'rejected' ? t('rejected') : (e.note || t('notAnalysed'));
      return `<div style="padding:8px 0;border-bottom:1px solid var(--line)"><div style="display:flex;gap:8px;align-items:center"><span class="dot" style="background:${lane(c.source_id)}"></span><b>${esc(c.owner)}, ${esc(c.device)}</b><span class="hint" style="margin-left:auto">${c.photos} ${esc(t('photosN'))}</span></div>
        <div class="hint" style="margin:3px 0 0 16px">${esc(note)}${c.applied_s ? ` <b style="color:var(--accent)">${esc(fmtSec(c.applied_s))} ${esc(t('applied'))}</b>` : ''}</div>
        <div style="display:flex;gap:6px;margin:6px 0 0 16px;align-items:center">${sug ? `<button class="btn small primary" data-ca="accept" data-c="${c.clock_id}">${esc(t('apply'))} ${esc(fmtSec(c.suggested_s))}</button>` : ''}
        <input type="number" step="1" placeholder="${esc(t('seconds'))}" data-in="${c.clock_id}" style="width:90px;padding:2px 6px;border:1px solid var(--line);border-radius:6px;background:var(--panel)">
        <button class="btn small" data-ca="manual" data-c="${c.clock_id}">${esc(t('set'))}</button>
        ${c.applied_s ? `<button class="btn small" data-ca="reset" data-c="${c.clock_id}">${esc(t('undo'))}</button>` : ''}${sug ? `<button class="btn small" data-ca="reject" data-c="${c.clock_id}">${esc(t('reject'))}</button>` : ''}</div></div>`;
    }).join('')}<p class="hint">${esc(t('clockHint'))}</p></div>`;
  }
  $('#main').innerHTML = html;
  $('#createBtn').onclick = async () => { const name = $('#newName').value.trim(); if (!name) return $('#newName').focus();
    const r = await post('/api/collections', {name}); if (r.error) return status(r.error, true); loadCollections(r.id); };
  document.querySelectorAll('[data-owner]').forEach(i => i.onchange = () => api(`/api/collections/${S.cid}/sources/${i.dataset.owner}`, {method: 'PATCH', body: JSON.stringify({owner: i.value})}).then(reload));
  const add = async browse => { const owner = $('#owner').value.trim(); if (!owner) { status(t('owner'), true); return $('#owner').focus(); }
    const r = await post(`/api/collections/${S.cid}/sources`, {owner, path: browse ? '' : $('#path').value.trim(), browse});
    if (r.cancelled) return; if (r.error) return status(r.error, true); status(''); reload(); };
  if ($('#browseBtn')) { $('#browseBtn').onclick = () => add(true); $('#addBtn').onclick = () => add(false); }
  document.querySelectorAll('[data-ca]').forEach(b => b.onclick = async () => {
    const body = {action: b.dataset.ca};
    if (b.dataset.ca === 'manual') { const v = document.querySelector(`[data-in="${b.dataset.c}"]`).value; if (v === '') return; body.seconds = +v; }
    const r = await post(`/api/collections/${S.cid}/clocks/${b.dataset.c}`, body); if (r.error) return status(r.error, true); reload(); });
}

/* ---------- settings ---------- */
async function viewSettings() {
  const s = S.settings, ai = await api('/api/ai/status');
  $('#main').innerHTML = `<div class="card"><div class="form">
      ${sel('setLang', t('language'), [['en', 'English'], ['sl', 'Slovenščina']], s.ui_language || 'en')}
      ${sel('setGpu', t('aiLimit'), [['25', t('gentle')], ['30', t('def30')], ['50', t('faster')], ['100', t('noLimit')]], String(s.ai_gpu_share ?? 30))}
      <div><label style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="setBat" ${s.ai_pause_on_battery ? 'checked' : ''}> ${esc(t('pauseBattery'))}</label></div></div></div>
    <div class="card"><h3>${esc(t('aiModels'))}</h3><dl style="display:grid;grid-template-columns:150px 1fr;gap:4px 10px;margin:0">
      <dt class="hint">${esc(t('searchModel'))}</dt><dd style="margin:0">${esc(ai.search_model)}: ${esc(ai.search_ready ? t('ready') : t('missing'))}</dd>
      <dt class="hint">${esc(t('descModel'))}</dt><dd style="margin:0">${esc(ai.vlm?.model)}: ${esc(ai.vlm?.running ? t('running') : t('notRunning'))}</dd></dl></div>
    <div class="card"><h3>${esc(t('keysTitle'))}</h3><p class="hint" style="margin:0">${esc(t('keysLib'))}<br>${esc(t('dupKeys'))}</p></div>`;
  const save = async () => { const r = await post('/api/settings', {ui_language: $('#setLang').value, ai_gpu_share: +$('#setGpu').value, ai_pause_on_battery: $('#setBat').checked});
    if (r.error) return status(r.error, true); S.settings = r.settings; const changed = lang !== S.settings.ui_language; lang = S.settings.ui_language;
    document.documentElement.lang = lang; status(t('saved')); if (changed) { applyStatic(); render(); } };
  ['setLang', 'setGpu', 'setBat'].forEach(id => $('#' + id).onchange = save);
}

/* ---------- jobs ---------- */
$('#indexBtn').onclick = async () => { if (!S.cid) return; const r = await post(`/api/collections/${S.cid}/index`); if (r.error) return status(r.error, true); checkJob(); };
$('#describeBtn').onclick = async () => {
  if (!S.cid) return;
  if ($('#describeBtn').dataset.running) { await api(`/api/collections/${S.cid}/index`, {method: 'DELETE'}); return; }
  const r = await post(`/api/collections/${S.cid}/describe`, {}); if (r.error) return status(r.error, true); checkJob(); };
async function checkJob() {
  clearTimeout(S.polling); if (!S.cid) return;
  const j = await api(`/api/collections/${S.cid}/index`);
  if (j.collection !== S.cid && !j.running) { $('#fill').style.width = '0'; return; }
  $('#fill').style.width = (j.progress || 0) + '%'; status(j.status || '', !!j.error);
  $('#indexBtn').disabled = j.running;
  const desc = j.running && /describ|local AI/i.test(j.status || '');
  $('#describeBtn').textContent = desc ? t('stopDescribe') : t('describe');
  if (desc) $('#describeBtn').dataset.running = '1'; else delete $('#describeBtn').dataset.running;
  $('#describeBtn').disabled = j.running && !desc;
  if (j.running) S.polling = setTimeout(checkJob, 500); else if (j.result) { reload(); }
}

/* ---------- zoom & keys ---------- */
function setZoom() { document.documentElement.style.setProperty('--tile', $('#zoom').value + 'px'); try { localStorage.setItem('pc-zoom', $('#zoom').value); } catch (e) {} }
$('#zoom').oninput = setZoom;
function gridColumns() {
  const g = document.querySelector('#main .grid'); if (!g) return 1;
  return getComputedStyle(g).gridTemplateColumns.split(' ').length || 1;
}
document.addEventListener('keydown', e => {
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
  const ql = !$('#quicklook').hidden;
  if (e.key === 'Escape') { if (ql) closeQL(); else closeInspector(); return; }
  if (S.view === 'duplicates') {
    const g = S.dups[S.dupG]; if (!g) return;
    if (e.key === 'ArrowDown') { S.dupG = Math.min(S.dups.length - 1, S.dupG + 1); S.dupC = 0; viewDuplicates(); e.preventDefault(); }
    if (e.key === 'ArrowUp') { S.dupG = Math.max(0, S.dupG - 1); S.dupC = 0; viewDuplicates(); e.preventDefault(); }
    if (e.key === 'ArrowRight') { S.dupC = Math.min(g.members.length - 1, S.dupC + 1); viewDuplicates(); e.preventDefault(); }
    if (e.key === 'ArrowLeft') { S.dupC = Math.max(0, S.dupC - 1); viewDuplicates(); e.preventDefault(); }
    if ((e.key === 'k' || e.key === 'K') && g.category !== 'similar_scene') keeper(S.dupG, g.members[S.dupC].id);
    return;
  }
  if (!S.list.length || !['library', 'timeline', 'best', 'search'].includes(S.view)) return;
  const cols = gridColumns(), it = S.list[S.sel];
  const move = d => { e.preventDefault(); select(Math.max(0, Math.min(S.list.length - 1, (S.sel < 0 ? 0 : S.sel + d)))); if (ql) quickLook(); };
  if (e.key === 'ArrowRight') return move(1);
  if (e.key === 'ArrowLeft') return move(-1);
  if (e.key === 'ArrowDown') return move(ql ? 1 : cols);
  if (e.key === 'ArrowUp') return move(ql ? -1 : -cols);
  if (e.key === ' ') { e.preventDefault(); if (ql) closeQL(); else quickLook(); return; }
  if (!it) return;
  if (e.key === '1') mark(it, {focus: 'sharp'});
  if (e.key === '2') mark(it, {focus: 'soft'});
  if (e.key === '3') mark(it, {focus: 'blurry'});
  if (e.key === '0') mark(it, {focus: null});
  if (e.key === 'b' || e.key === 'B') mark(it, {wallpaper: !it.wallpaper});
  if ((e.key === 'x' || e.key === 'X') && S.view === 'best') mark(it, {excluded: true});
});

/* best view shows score bars in the inspector */
const _inspector = inspector;
inspector = function (it) { _inspector(it); if (S.view === 'best' && it && it.scores) $('#inspector').insertAdjacentHTML('beforeend', bestInspectorExtra(it)); };

boot();
