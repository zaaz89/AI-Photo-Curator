/* Photo Curator: the trip workflow app (macOS HIG style) over the collection API (app/web/timeline_bp.py). */
'use strict';

/* ---------- icons (SF Symbols-style line icons) ---------- */
const ICON = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  stack: '<rect x="7" y="7" width="13" height="13" rx="2"/><path d="M4 16V6a2 2 0 0 1 2-2h10"/>',
  blur: '<circle cx="12" cy="12" r="8" stroke-dasharray="2 3"/><circle cx="12" cy="12" r="3"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  text: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  share: '<path d="M12 3v12M8 7l4-4 4 4"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-8 8"/>',
  star: '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>',
  heart: '<path d="M12 20s-7-4.4-9.2-8.6C1.3 8.4 3 5 6.4 5c2 0 3.3 1.1 4 2.3h3.2C14.3 6.1 15.6 5 17.6 5 21 5 22.7 8.4 21.2 11.4 19 15.6 12 20 12 20z"/>',
  xmark: '<path d="M6 6l12 12M18 6L6 18"/>',
  undo: '<path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-2"/>',
  check: '<path d="M5 12l5 5 9-10"/>',
  play: '<path d="M8 5v14l11-7z"/>',
  phone: '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 18h2"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
};
const icon = (n, extra = '') => `<svg class="i" viewBox="0 0 24 24" aria-hidden="true" ${extra}>${ICON[n] || ''}</svg>`;

/* ---------- language ---------- */
const STR = {
  en: {
    trip: 'Trip', newTrip: 'New trip', noTrips: 'No trips yet', reanalyse: 'Analyse again', thumbSize: 'Thumbnail size',
    searchPh: 'Search: sunset, ring, Firence', stepsSec: 'Trip', browseSec: 'Browse', settings: 'Settings',
    s_import: 'Photos and people', s_times: 'Check times', s_duplicates: 'Best of each moment', s_blurry: 'Blurry photos',
    s_events: 'Days and events', s_descriptions: 'Descriptions', s_export: 'Export for Google Photos',
    library: 'All photos', best: 'Best photos', search: 'Search results',
    lead_import: 'One folder per person. The folders are only read; nothing is ever written into them.',
    lead_times: 'Two phones rarely show the same time. When a device clock is off, apply the suggested correction or enter your own. Files are not changed.',
    lead_duplicates: 'Bursts and near-identical shots. The best frame is chosen by eyes open, looking at the camera, a sharp face, focus and overall look. Keep a different one with K or a click.',
    lead_blurry: 'Photos that look out of focus. Keep the ones you like anyway; the rest are left out of the export.',
    lead_events: 'Each day is split into events by time and place. Rename or merge events here; select photos to move them to another event.',
    lead_descriptions: 'A short description and tags for every photo, made on this Mac. They go into the exported copies so Google Photos can show and search them.',
    lead_export: 'One folder with every kept photo, ready to drag into Google Photos. Live Photo videos stay next to their stills. Corrected time, place and description are written into the copies; your originals stay untouched.',
    markDone: 'Mark as done', done: 'Done', nextStep: 'Next', all: 'All', favorites: 'Favourites', rejected: 'Left out',
    videos: 'Videos', sharp: 'Sharp', soft: 'Soft', blurry: 'Blurry', auto: 'Auto',
    sort: 'Sort', s_time: 'Time', s_person: 'Person', s_place: 'Place', s_quality: 'Quality',
    photosN: 'photos', items: 'items', selected: 'selected', favorite: 'Favourite', unfavorite: 'Remove favourite',
    reject: 'Leave out', restore: 'Keep', moveTo: 'Move to event', wallpaper: 'Phone wallpaper', clear: 'Clear', undo: 'Undo',
    undone: 'Undone.', marked: 'Updated', emptyTrip: 'Start with a trip', emptyTripHint: 'Choose New trip, name it, and add one folder per person.',
    emptyIdx: 'Nothing analysed yet', emptyIdxHint: 'Add the folders in Photos and people; the analysis starts by itself.',
    noMatch: 'No photos match these filters.', captureTime: 'Capture time', place: 'Place', source: 'Person',
    device: 'Device', size: 'Size', file: 'File', unknownNoGps: 'unknown (no GPS)', kmFrom: 'km from the centre', fromGps: 'from GPS',
    clockFix: 'Clock fix', fileSays: 'The file says', focus: 'Focus', faces: 'Faces', eyesOpen: 'eyes open', eyesClosed: 'eyes may be closed',
    lookAway: 'looking away', lookingCam: 'looking at the camera', aiDesc: 'Description (local AI, not verified)', textInPhoto: 'Text in the photo',
    howTime: 'How the time was decided', splitHere: 'Start a new event here', rename: 'Rename', mergePrev: 'Merge with previous',
    undoDay: 'Undo my changes for this day', eventName: 'Event name', newEventName: 'Name of the new event', newEvent: 'New event…',
    namedByYou: 'named by you', identical: 'Identical files', near: 'Near-identical shots',
    keep: 'Keep', keepThis: 'Keep this one', useRec: 'Use the recommendation', dupKeys: '↑ ↓ moment · ← → photo · K keep · Space enlarge',
    noDups: 'No duplicates', noDupsHint: 'Every moment has one photo.', noBlurry: 'No blurry photos', noBlurryHint: 'Every photo looks in focus.',
    leaveOutAll: 'Leave out all blurry', personName: 'Name', chooseFolder: 'Choose folder…',
    tripName: 'Trip name', tripNamePh: 'e.g. Tuscany 2026', create: 'Create and analyse', cancel: 'Cancel', person1: 'Me', person2: 'Partner',
    wizardTitle: 'New trip', wizardLead: 'Name the trip and choose one folder per person, for example on the Desktop. The folders are only read.',
    needName: 'Give the trip a name.', needFolder: 'Choose at least one folder.', files_: 'files', addFolder: 'Add another person',
    clocks: 'Device clocks', reference: 'Reference: the others are aligned to this clock.', rejectedS: 'Suggestion rejected.',
    notAnalysed: 'Not analysed yet.', apply: 'Apply', set: 'Set', rejectS: 'Reject', seconds: 'seconds', applied: 'applied',
    described: 'described', describeNow: 'Describe photos', stopDescribe: 'Stop', describeHint: 'Runs on this Mac within the GPU limit from Settings, about 8 s per photo at the default limit. Already described photos are skipped.',
    gpExport: 'Export for Google Photos', gpWhat: 'Included: every kept photo and video, favourites marked with 5 stars. Left out: photos you left out, blurry photos (unless favourite) and extra frames of the same moment.',
    preview: 'Preview', chooseDest: 'Choose folder and export', custom: 'Custom export', fileNames: 'File names', foldersL: 'Folders',
    dupsOpt: 'Extra frames of the same moment', selection: 'Which photos', selAll: 'All', selNoBlurry: 'All except blurry', selBest: 'Best only',
    leaveOutOpt: 'Leave out', alternatives: 'Put in Alternatives/', includeToo: 'Include', byDayPlace: 'By day and place', byDay: 'By day',
    byEvent: 'By day and event', byPlace: 'By place', oneFolder: 'One folder', files: 'files', newPath: 'New name',
    original: 'Original', paired: 'paired', alternative: 'alternative', showing: 'Showing', of: 'of', writesMeta: 'time, place and description written into the copies',
    exportStarted: 'Export started.', cancelled: 'Cancelled.', chooseDialog: 'Choose a folder in the dialog…', searching: 'Searching…',
    alsoAs: 'also searched as', simGuess: 'ordered by similarity', placeMatch: 'place', tagMatch: 'tag', bestOf: 'results for',
    weights: 'Ranking', composition: 'Composition', technical: 'Technical', sharpness: 'Sharpness', color: 'Colour', aesthetic: 'Overall look',
    resetWeights: 'Reset', topN: 'How many', bestHint: 'Ranked by the weighted score. Left-out and blurry photos and extra frames are skipped.',
    exportThese: 'Export these', exportWall: 'Export phone wallpapers', language: 'Language', aiLimit: 'How hard local AI may work',
    gentle: 'Gentle (about 25 % GPU time)', def30: 'Default (about 30 %)', faster: 'Faster (about 50 %)', noLimit: 'No limit (gets warm)',
    pauseBattery: 'Pause on battery', keeperW: 'Choosing the best of a moment', w_faces: 'Faces (eyes, gaze)', w_focus: 'Focus', w_look: 'Overall look',
    w_resolution: 'Resolution', aiModels: 'Local AI', searchModel: 'Search', descModel: 'Descriptions', facesModel: 'Faces',
    ready: 'ready', missing: 'missing', running: 'running', notRunning: 'starts when needed', saved: 'Saved.', keysTitle: 'Keyboard',
    keysLib: 'Arrows move · Space enlarge · F favourite · X leave out · 1 2 3 focus · ⌘ or ⇧ click selects several · ⌘Z undo · Esc close',
    exportDone: 'Export finished and verified.', exportFailed: 'Export finished with problems; see the manifest in the folder.', showInFinder: 'Show in Finder', close: 'Close',
    confText: {high: 'exact', medium: 'time zone assumed', low: 'camera clock only', unknown: 'no capture time'}, undated: 'No date',
  },
  sl: {
    trip: 'Potovanje', newTrip: 'Novo potovanje', noTrips: 'Ni še potovanj', reanalyse: 'Analiziraj znova', thumbSize: 'Velikost sličic',
    searchPh: 'Išči: sončni zahod, prstan, Firence', stepsSec: 'Potovanje', browseSec: 'Pregled', settings: 'Nastavitve',
    s_import: 'Fotografije in osebe', s_times: 'Preveri čas', s_duplicates: 'Najboljše iz trenutka', s_blurry: 'Zamegljene fotografije',
    s_events: 'Dnevi in dogodki', s_descriptions: 'Opisi', s_export: 'Izvoz za Google Photos',
    library: 'Vse fotografije', best: 'Najboljše', search: 'Rezultati iskanja',
    lead_import: 'Ena mapa za vsako osebo. Mape se samo berejo, vanje se nikoli nič ne zapiše.',
    lead_times: 'Dva telefona redko kažeta isti čas. Če ura naprave ne drži, uporabi predlagani popravek ali vnesi svojega. Datoteke se ne spremenijo.',
    lead_duplicates: 'Zaporedni in skoraj enaki posnetki. Najboljši je izbran po odprtih očeh, pogledu v kamero, ostrem obrazu, ostrini in skupnem vtisu. Drugega obdržiš s K ali klikom.',
    lead_blurry: 'Fotografije, ki niso ostre. Tiste, ki ti vseeno ugajajo, obdrži; ostale se ne izvozijo.',
    lead_events: 'Vsak dan je razdeljen na dogodke po času in kraju. Tukaj jih preimenuješ ali združiš; izberi fotografije, da jih premakneš v drug dogodek.',
    lead_descriptions: 'Kratek opis in oznake za vsako fotografijo, narejeni na tem Macu. Zapišejo se v izvožene kopije, da jih Google Photos pokaže in najde.',
    lead_export: 'Ena mapa z vsemi obdržanimi fotografijami, pripravljena za Google Photos. Videi Live Photo ostanejo ob fotografijah. Popravljen čas, kraj in opis se zapišejo v kopije, izvirniki ostanejo nedotaknjeni.',
    markDone: 'Označi kot opravljeno', done: 'Opravljeno', nextStep: 'Naprej', all: 'Vse', favorites: 'Priljubljene', rejected: 'Izpuščene',
    videos: 'Videi', sharp: 'Ostre', soft: 'Mehke', blurry: 'Zamegljene', auto: 'Samodejno',
    sort: 'Razvrsti', s_time: 'Čas', s_person: 'Oseba', s_place: 'Kraj', s_quality: 'Kakovost',
    photosN: 'fotografij', items: 'elementov', selected: 'izbranih', favorite: 'Priljubljena', unfavorite: 'Odstrani priljubljeno',
    reject: 'Izpusti', restore: 'Obdrži', moveTo: 'Premakni v dogodek', wallpaper: 'Ozadje za telefon', clear: 'Počisti', undo: 'Razveljavi',
    undone: 'Razveljavljeno.', marked: 'Posodobljeno', emptyTrip: 'Začni s potovanjem', emptyTripHint: 'Izberi Novo potovanje, ga poimenuj in dodaj mapo za vsako osebo.',
    emptyIdx: 'Nič še ni analizirano', emptyIdxHint: 'Dodaj mape v Fotografije in osebe; analiza se začne sama.',
    noMatch: 'Nobena fotografija ne ustreza filtrom.', captureTime: 'Čas zajema', place: 'Kraj', source: 'Oseba',
    device: 'Naprava', size: 'Velikost', file: 'Datoteka', unknownNoGps: 'neznan (ni GPS)', kmFrom: 'km od središča', fromGps: 'iz GPS',
    clockFix: 'Popravek ure', fileSays: 'V datoteki piše', focus: 'Ostrina', faces: 'Obrazi', eyesOpen: 'oči odprte', eyesClosed: 'oči morda zaprte',
    lookAway: 'gleda stran', lookingCam: 'gleda v kamero', aiDesc: 'Opis (lokalni AI, ni preverjen)', textInPhoto: 'Besedilo na fotografiji',
    howTime: 'Kako je bil čas določen', splitHere: 'Začni nov dogodek tukaj', rename: 'Preimenuj', mergePrev: 'Združi s prejšnjim',
    undoDay: 'Razveljavi moje spremembe za ta dan', eventName: 'Ime dogodka', newEventName: 'Ime novega dogodka', newEvent: 'Nov dogodek…',
    namedByYou: 'poimenoval ti', identical: 'Enake datoteke', near: 'Skoraj enaki posnetki',
    keep: 'Obdrži', keepThis: 'Obdrži tega', useRec: 'Uporabi priporočilo', dupKeys: '↑ ↓ trenutek · ← → fotografija · K obdrži · preslednica poveča',
    noDups: 'Ni dvojnikov', noDupsHint: 'Vsak trenutek ima eno fotografijo.', noBlurry: 'Ni zamegljenih', noBlurryHint: 'Vse fotografije so videti ostre.',
    leaveOutAll: 'Izpusti vse zamegljene', personName: 'Ime', chooseFolder: 'Izberi mapo…',
    tripName: 'Ime potovanja', tripNamePh: 'npr. Toskana 2026', create: 'Ustvari in analiziraj', cancel: 'Prekliči', person1: 'Jaz', person2: 'Partnerka',
    wizardTitle: 'Novo potovanje', wizardLead: 'Poimenuj potovanje in izberi mapo za vsako osebo, na primer na namizju. Mape se samo berejo.',
    needName: 'Potovanje poimenuj.', needFolder: 'Izberi vsaj eno mapo.', files_: 'datotek', addFolder: 'Dodaj še eno osebo',
    clocks: 'Ure naprav', reference: 'Referenca: druge so poravnane na to uro.', rejectedS: 'Predlog zavrnjen.',
    notAnalysed: 'Še ni analizirano.', apply: 'Uporabi', set: 'Nastavi', rejectS: 'Zavrni', seconds: 'sekunde', applied: 'uporabljeno',
    described: 'opisanih', describeNow: 'Opiši fotografije', stopDescribe: 'Ustavi', describeHint: 'Teče na tem Macu v okviru omejitve GPU iz Nastavitev, pri privzeti omejitvi okoli 8 s na fotografijo. Že opisane se preskočijo.',
    gpExport: 'Izvoz za Google Photos', gpWhat: 'Vključeno: vse obdržane fotografije in videi, priljubljene s 5 zvezdicami. Izpuščeno: izpuščene, zamegljene (razen priljubljenih) in odvečni posnetki istega trenutka.',
    preview: 'Predogled', chooseDest: 'Izberi mapo in izvozi', custom: 'Izvoz po meri', fileNames: 'Imena datotek', foldersL: 'Mape',
    dupsOpt: 'Odvečni posnetki istega trenutka', selection: 'Katere fotografije', selAll: 'Vse', selNoBlurry: 'Vse razen zamegljenih', selBest: 'Samo najboljše',
    leaveOutOpt: 'Izpusti', alternatives: 'V Alternatives/', includeToo: 'Vključi', byDayPlace: 'Po dnevu in kraju', byDay: 'Po dnevu',
    byEvent: 'Po dnevu in dogodku', byPlace: 'Po kraju', oneFolder: 'Ena mapa', files: 'datotek', newPath: 'Novo ime',
    original: 'Izvirnik', paired: 'par', alternative: 'alternativa', showing: 'Prikazanih', of: 'od', writesMeta: 'čas, kraj in opis zapisani v kopije',
    exportStarted: 'Izvoz se je začel.', cancelled: 'Preklicano.', chooseDialog: 'Izberi mapo v oknu…', searching: 'Iščem…',
    alsoAs: 'iskano tudi kot', simGuess: 'razvrščeno po podobnosti', placeMatch: 'kraj', tagMatch: 'oznaka', bestOf: 'zadetkov za',
    weights: 'Razvrščanje', composition: 'Kompozicija', technical: 'Tehnika', sharpness: 'Ostrina', color: 'Barve', aesthetic: 'Skupni vtis',
    resetWeights: 'Ponastavi', topN: 'Koliko', bestHint: 'Razvrščeno po uteženi oceni. Izpuščene, zamegljene in odvečni posnetki so preskočeni.',
    exportThese: 'Izvozi te', exportWall: 'Izvozi ozadja za telefon', language: 'Jezik', aiLimit: 'Kako močno sme delati lokalni AI',
    gentle: 'Nežno (okoli 25 % časa GPU)', def30: 'Privzeto (okoli 30 %)', faster: 'Hitreje (okoli 50 %)', noLimit: 'Brez omejitve (se segreje)',
    pauseBattery: 'Premor na bateriji', keeperW: 'Izbira najboljšega iz trenutka', w_faces: 'Obrazi (oči, pogled)', w_focus: 'Ostrina', w_look: 'Skupni vtis',
    w_resolution: 'Ločljivost', aiModels: 'Lokalni AI', searchModel: 'Iskanje', descModel: 'Opisi', facesModel: 'Obrazi',
    ready: 'pripravljen', missing: 'manjka', running: 'teče', notRunning: 'se zažene po potrebi', saved: 'Shranjeno.', keysTitle: 'Tipkovnica',
    keysLib: 'Puščice premik · preslednica poveča · F priljubljena · X izpusti · 1 2 3 ostrina · ⌘ ali ⇧ klik izbere več · ⌘Z razveljavi · Esc zapre',
    exportDone: 'Izvoz je končan in preverjen.', exportFailed: 'Izvoz je končan s težavami; poglej manifest v mapi.', showInFinder: 'Pokaži v Finderju', close: 'Zapri',
    confText: {high: 'natančen', medium: 'časovni pas predpostavljen', low: 'samo ura naprave', unknown: 'ni časa zajema'}, undated: 'Brez datuma',
  },
};
let lang = 'en';
const t = k => (STR[lang] && STR[lang][k]) ?? STR.en[k] ?? k;
const WARN_SL = {'duplicates skipped': 'odvečnih posnetkov izpuščenih', 'no place (no GPS)': 'brez kraja (ni GPS)',
  'no trustworthy capture time': 'brez zanesljivega časa', 'paired files kept together': 'parov ohranjenih skupaj', 'rejected by you': 'izpustil ti'};
const tw = k => lang === 'sl' ? (WARN_SL[k] || k.replace(/^left out by selection \((.*)\)$/, 'izpuščenih zaradi izbire ($1)')) : k;

/* ---------- helpers ---------- */
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
const api = (url, opt = {}) => fetch(url, {headers: {'Content-Type': 'application/json'}, ...opt}).then(r => r.json());
const post = (url, body) => api(url, {method: 'POST', body: JSON.stringify(body || {})});
const store = {get: k => { try { return localStorage.getItem(k); } catch (e) { return null; } },
               set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } }};
const LANES = ['#0a84ff', '#ff9f0a', '#bf5af2', '#30d158', '#ff375f', '#64d2ff'];
const S = {cid: null, data: null, dups: [], clocks: [], settings: {}, wf: {}, view: 's_import', sel: new Set(), cursor: -1, list: [],
           filter: {state: 'all', focus: 'all', source: 'all'}, sort: 'time', searchRes: null, undo: [], plan: null,
           exportOpts: {template: 'default', folders: 'day', duplicates: 'skip', selection: 'all', topn: 50}, dupG: 0, dupC: 0, polling: null, groups: []};
const sourceIndex = sid => Math.max(0, (S.data?.sources || []).findIndex(s => s.id === sid));
const lane = sid => LANES[sourceIndex(sid) % LANES.length];
const thumbOf = it => it.kind === 'video' ? (it.poster ? `/api/collections/${S.cid}/poster/${it.id}` : '') : `/api/thumb?path=${encodeURIComponent(it.path)}&v=2`;
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
const fmtDur = s => s == null ? '' : `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`;
const fmtOffset = m => m == null ? '' : `${m < 0 ? '−' : '+'}${String(Math.abs(m) / 60 | 0).padStart(2, '0')}:${String(Math.abs(m) % 60).padStart(2, '0')}`;
let toastTimer;
function toast(msg, undoable) {
  const el = $('#toast'); el.hidden = false;
  el.innerHTML = `<span>${esc(msg)}</span>${undoable ? `<button class="link" id="toastUndo">${esc(t('undo'))}</button>` : ''}`;
  if (undoable) $('#toastUndo').onclick = undoLast;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, 5000);
}
const empty = (a, b, extra = '') => `<div class="empty"><strong>${esc(t(a))}</strong><p>${esc(t(b))}</p>${extra}</div>`;

/* ---------- boot and loading ---------- */
async function boot() {
  const st = await api('/api/settings'); S.settings = st.settings || {}; lang = S.settings.ui_language || 'en';
  document.documentElement.lang = lang;
  $('#newTrip').innerHTML = icon('plus'); $('#searchIcon').innerHTML = icon('search');
  applyStatic();
  $('#zoom').value = store.get('pc-zoom') || 170;
  setZoom();
  await loadTrips();
}
function applyStatic() {
  document.querySelectorAll('[data-t]').forEach(el => { el.textContent = t(el.dataset.t); });
  document.querySelectorAll('[data-tp]').forEach(el => { el.placeholder = t(el.dataset.tp); });
  document.querySelectorAll('[data-ta]').forEach(el => { el.title = t(el.dataset.ta); el.setAttribute('aria-label', t(el.dataset.ta)); });
}
async function loadTrips(select) {
  const d = await api('/api/collections'); const list = d.collections || [];
  $('#coll').innerHTML = list.length ? list.map(c => `<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('') : `<option value="">${esc(t('noTrips'))}</option>`;
  const want = select || store.get('pc-coll');
  if (want && list.some(c => c.id === want)) $('#coll').value = want;
  S.cid = $('#coll').value || null;
  restoreView();
  await reload(); checkJob();
  if (!list.length) openWizard();
}
function restoreView() {
  S.view = store.get('pc-view:' + S.cid) || 's_import';
  if (S.view === 'search') S.view = 'library';
}
$('#coll').onchange = () => {
  S.cid = $('#coll').value; store.set('pc-coll', S.cid); restoreView();
  S.sel.clear(); S.cursor = -1; S.searchRes = null; S.plan = null; S.undo = []; closeInspector(); reload(); checkJob();
};
$('#newTrip').onclick = () => openWizard();
async function reload() {
  if (!S.cid) { S.data = null; render(); return; }
  const [data, dups, clocks, sources, wf] = await Promise.all([
    api(`/api/collections/${S.cid}/timeline`), api(`/api/collections/${S.cid}/duplicates`), api(`/api/collections/${S.cid}/clocks`),
    api(`/api/collections/${S.cid}/sources`), api(`/api/collections/${S.cid}/workflow`)]);
  S.data = data; S.data.items = data.items || []; S.data.sources = sources.sources || [];
  S.dups = dups.groups || []; S.clocks = clocks.clocks || [];
  S.wf = {}; (wf.steps || []).forEach(s => { S.wf[s.step] = s.done; });
  render();
}

/* ---------- navigation ---------- */
const STEPS = [['s_import', 'import'], ['s_times', 'times'], ['s_duplicates', 'duplicates'], ['s_blurry', 'blurry'],
               ['s_events', 'events'], ['s_descriptions', 'descriptions'], ['s_export', 'export']];
const BROWSE = [['library', 'photo'], ['best', 'star'], ['search', 'search']];
const GRID_VIEWS = ['library', 's_events', 's_blurry', 'best', 'search'];
function counts() {
  const items = S.data?.items || [];
  if (!S.data) return {};
  return {library: items.filter(i => !i.rejected).length, search: S.searchRes ? (S.searchRes.results || []).length : null,
          s_import: (S.data.sources || []).length || null, s_duplicates: S.dups.filter(g => g.category !== 'similar_scene').length || null,
          s_blurry: items.filter(i => i.focus?.tier === 'blurry' && !i.rejected).length || null, s_events: (S.data.events || []).length || null,
          s_descriptions: items.length ? `${S.data.summary?.described || 0}/${items.filter(i => i.kind === 'image').length}` : null};
}
function renderNav() {
  const c = counts();
  const btn = (v, ic, label) => `<button data-v="${v}" ${S.view === v ? 'aria-current="page"' : ''}>${ic}<span class="lbl">${esc(label)}</span>${c[v] != null ? `<small>${esc(c[v])}</small>` : ''}</button>`;
  $('#nav').innerHTML = `<div class="sec">${esc(t('stepsSec'))}</div>` +
    STEPS.map(([v, step], i) => btn(v, `<span class="step-n ${S.wf[step] ? 'done' : ''}" aria-label="${S.wf[step] ? esc(t('done')) : i + 1}">${S.wf[step] ? icon('check') : i + 1}</span>`, t(v))).join('') +
    `<div class="sec">${esc(t('browseSec'))}</div>` + BROWSE.filter(([v]) => v !== 'search' || S.searchRes).map(([v, ic]) => btn(v, icon(ic), t(v))).join('') +
    `<div class="sec" aria-hidden="true"></div>` + btn('settings', icon('gear'), t('settings'));
  document.querySelectorAll('#nav [data-v]').forEach(b => { b.onclick = () => go(b.dataset.v); });
}
function go(v) { S.view = v; S.sel.clear(); S.cursor = -1; store.set('pc-view:' + S.cid, v); closeInspector(); render(); $('#main').scrollTop = 0; $('#main').focus({preventScroll: true}); }
function render() {
  renderNav(); renderSelbar();
  const step = STEPS.find(s => s[0] === S.view);
  $('#title').textContent = t(S.view);
  $('#subtitle').textContent = S.data && S.cid ? `${S.data.items.length} ${t('photosN')}` : '';
  $('#tools').innerHTML = ''; $('#tools').hidden = false;
  const m = $('#main');
  S.list = [];
  if (!S.cid && S.view !== 'settings') { m.innerHTML = empty('emptyTrip', 'emptyTripHint', `<button class="btn primary" id="emptyNew">${icon('plus')}${esc(t('newTrip'))}</button>`); $('#emptyNew').onclick = openWizard; return; }
  const needsData = !['s_import', 'settings', 's_times'].includes(S.view);
  if (needsData && !(S.data?.items || []).length) { m.innerHTML = empty('emptyIdx', 'emptyIdxHint'); return; }
  const views = {s_import: viewImport, s_times: viewTimes, s_duplicates: viewDuplicates, s_blurry: viewBlurry, s_events: viewEvents,
                 s_descriptions: viewDescriptions, s_export: viewExport, library: viewLibrary, best: viewBest, search: viewSearch, settings: viewSettings};
  (views[S.view] || viewLibrary)();
  if (step) stepChrome(step);
  if (!$('#tools').innerHTML) $('#tools').hidden = true;
}
function stepChrome(step) {
  const m = $('#main'), i = STEPS.indexOf(step), next = STEPS[i + 1], done = S.wf[step[1]];
  m.insertAdjacentHTML('afterbegin', `<div class="stephead"><p class="lead">${esc(t('lead_' + step[1]))}</p>
    <div class="stepbar"><button class="btn" id="doneBtn" aria-pressed="${!!done}">${done ? icon('check') + esc(t('done')) : esc(t('markDone'))}</button>
    ${next ? `<button class="btn primary" id="nextBtn">${esc(t('nextStep'))}: ${esc(t(next[0]))}</button>` : ''}</div></div>`);
  $('#doneBtn').onclick = async () => { await setStep(step[1], !S.wf[step[1]]); render(); };
  if (next) $('#nextBtn').onclick = async () => { if (!S.wf[step[1]]) await setStep(step[1], true); go(next[0]); };
}
async function setStep(step, done) { await post(`/api/collections/${S.cid}/workflow`, {step, done}); S.wf[step] = done; }

/* ---------- tiles and selection ---------- */
function tile(it, idx, extraTL = '') {
  const p = local(it), b = [];
  if (it.focus && it.focus.tier !== 'sharp' && it.kind === 'image') b.push(`<span class="bd ${esc(it.focus.tier)}">${esc(t(it.focus.tier))}</span>`);
  if (it.duplicate && it.duplicate.category !== 'similar_scene' && it.duplicate.keeper === false) b.push(`<span class="bd" title="${esc(t('near'))}">${icon('stack')}</span>`);
  if (it.faces?.eyes_closed) b.push(`<span class="bd warn" title="${esc(t('eyesClosed'))}">${icon('eye')}</span>`);
  const src = thumbOf(it);
  const img = src ? `<img loading="lazy" alt="" src="${src}">` : `<span class="vidph">${icon('play')}</span>`;
  const label = `${it.filename}, ${p.day} ${p.time.slice(0, 5)}, ${it.owner}${it.favorite ? ', ' + t('favorite') : ''}${it.rejected ? ', ' + t('rejected') : ''}`;
  return `<button class="tile ${it.rejected ? 'rej' : ''}" role="option" data-i="${idx}" tabindex="${idx === Math.max(S.cursor, 0) ? 0 : -1}" aria-selected="${S.sel.has(idx)}" aria-label="${esc(label)}">${img}
    <span class="tl">${extraTL}${b.join('')}</span><span class="tr">${it.favorite ? `<span class="heart">${icon('heart')}</span>` : ''}</span>
    ${it.kind === 'video' ? `<span class="dur">${icon('play')} ${esc(fmtDur(it.duration))}</span>` : ''}
    <span class="cap"><span>${esc(p.time.slice(0, 5))}</span><span>${esc(it.owner)}</span></span>
    <span class="lane" style="background:${lane(it.source_id)}"></span></button>`;
}
function bindTiles() {
  document.querySelectorAll('#main .grid').forEach(g => { if (g.querySelector('.tile[data-i]')) { g.setAttribute('role', 'listbox'); g.setAttribute('aria-multiselectable', 'true'); g.setAttribute('aria-label', t(S.view)); } });
  document.querySelectorAll('#main .tile[data-i]').forEach(el => {
    el.onfocus = () => { if (S.cursor < 0) { S.cursor = +el.dataset.i; } };
    el.onclick = e => clickTile(+el.dataset.i, e);
    el.ondblclick = () => quickLook();
  });
}
function clickTile(i, e) {
  if (e && (e.metaKey || e.ctrlKey)) { if (S.sel.has(i)) S.sel.delete(i); else S.sel.add(i); S.cursor = i; }
  else if (e && e.shiftKey && S.cursor >= 0) { const [a, b] = [Math.min(S.cursor, i), Math.max(S.cursor, i)]; for (let k = a; k <= b; k++) S.sel.add(k); }
  else { S.sel = new Set([i]); S.cursor = i; }
  paintSelection();
}
function paintSelection() {
  document.querySelectorAll('#main .tile[data-i]').forEach(el => { const i = +el.dataset.i; el.setAttribute('aria-selected', S.sel.has(i)); el.tabIndex = i === S.cursor ? 0 : -1; });
  const el = document.querySelector(`#main .tile[data-i="${S.cursor}"]`);
  if (el) { el.focus({preventScroll: true}); el.scrollIntoView({block: 'nearest'}); }
  if (S.sel.size === 1) inspector(S.list[[...S.sel][0]]); else closeInspector();
  renderSelbar();
}
const selected = () => [...S.sel].map(i => S.list[i]).filter(Boolean);
function renderSelbar() {
  const bar = $('#selbar'), items = selected();
  if (items.length < 2 || !GRID_VIEWS.includes(S.view)) { bar.hidden = true; return; }
  bar.hidden = false;
  const evs = S.data.events || [];
  bar.innerHTML = `<b>${items.length} ${esc(t('selected'))}</b>
    <button class="btn small" data-b="fav">${icon('heart')}${esc(t('favorite'))}</button>
    <button class="btn small" data-b="rej">${icon('xmark')}${esc(t('reject'))}</button>
    <button class="btn small" data-b="keep">${icon('check')}${esc(t('restore'))}</button>
    <select class="pop" id="moveSel" aria-label="${esc(t('moveTo'))}"><option value="">${esc(t('moveTo'))}…</option>${evs.map(e => `<option value="${e.id}">${esc(e.day)} · ${esc(e.name)}</option>`).join('')}<option value="new">${esc(t('newEvent'))}</option></select>
    <button class="btn small" data-b="clear">${esc(t('clear'))}</button>`;
  bar.querySelectorAll('[data-b]').forEach(b => { b.onclick = () => {
    const a = b.dataset.b;
    if (a === 'fav') return markMany(items, {favorite: !items.every(x => x.favorite)});
    if (a === 'rej') return markMany(items, {rejected: true});
    if (a === 'keep') return markMany(items, {rejected: false});
    S.sel.clear(); paintSelection();
  }; });
  $('#moveSel').onchange = async e => {
    const v = e.target.value; if (!v) return;
    const body = {asset_ids: items.map(i => i.id), event_id: v === 'new' ? null : +v};
    if (v === 'new') { const name = await ask(t('newEventName'), ''); if (name === null) { e.target.value = ''; return; } body.name = name; }
    const r = await post(`/api/collections/${S.cid}/events/move`, body); if (r.error) return status(r.error, true);
    toast(`${items.length} ${t('photosN')}: ${t('moveTo').toLowerCase()}`); S.sel.clear(); reload();
  };
}

/* ---------- sheets: keep keyboard focus inside, give it back on close ---------- */
let sheetReturn = null;
function sheetOpened() { if (!sheetReturn) sheetReturn = document.activeElement; }
function sheetClosed() { const el = sheetReturn; sheetReturn = null; if (el && document.contains(el)) el.focus({preventScroll: true}); }
$('#sheet').addEventListener('keydown', e => {
  if (e.key !== 'Tab') return;
  const f = [...$('#sheet').querySelectorAll('button,input,select,textarea,[tabindex]:not([tabindex="-1"])')].filter(x => !x.disabled && x.offsetParent);
  if (!f.length) return;
  const first = f[0], last = f[f.length - 1];
  if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
  else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
});

/* ---------- small text dialog (sheet; window.prompt does not exist in the Mac app) ---------- */
function ask(title, value) {
  return new Promise(resolve => {
    const sh = $('#sheet'); sheetOpened(); sh.hidden = false;
    sh.innerHTML = `<form class="sheet" role="dialog" aria-modal="true" aria-labelledby="askT"><h2 id="askT">${esc(title)}</h2>
      <input type="text" id="askIn" value="${esc(value)}" style="width:100%" aria-labelledby="askT">
      <div class="foot"><button type="button" class="btn" id="askNo">${esc(t('cancel'))}</button><button class="btn primary" type="submit">OK</button></div></form>`;
    const done = v => { sh.hidden = true; sh.innerHTML = ''; sheetClosed(); resolve(v); };
    sh.querySelector('form').onsubmit = e => { e.preventDefault(); done($('#askIn').value.trim()); };
    $('#askNo').onclick = () => done(null);
    sh.onkeydown = e => { if (e.key === 'Escape') { e.stopPropagation(); done(null); } };
    $('#askIn').focus(); $('#askIn').select();
  });
}

/* ---------- marks with undo ---------- */
async function markMany(items, fields) {
  if (!items.length) return;
  const prev = items.map(it => ({id: it.id, fields: Object.fromEntries(Object.keys(fields).map(k => [k, k === 'focus' ? (it.focus?.override ?? null) : !!it[k]]))}));
  const r = await post(`/api/collections/${S.cid}/marks/batch`, {asset_ids: items.map(i => i.id), ...fields});
  if (r.error) return status(r.error, true);
  S.undo.push(prev); if (S.undo.length > 50) S.undo.shift();
  toast(`${t('marked')}: ${items.length} ${t('photosN')}`, true);
  await refreshKeepSelection();
}
async function undoLast() {
  const prev = S.undo.pop(); if (!prev) return;
  for (const p of prev) await post(`/api/collections/${S.cid}/marks`, {asset_id: p.id, ...p.fields});
  toast(t('undone')); await refreshKeepSelection();
}
async function refreshKeepSelection() {
  const ids = new Set(selected().map(i => i.id)), curId = S.list[S.cursor]?.id, scroll = $('#main').scrollTop;
  await reload();
  S.sel = new Set(S.list.map((it, i) => ids.has(it.id) ? i : -1).filter(i => i >= 0));
  S.cursor = S.list.findIndex(it => it.id === curId);
  $('#main').scrollTop = scroll; paintSelection();
}

/* ---------- inspector ---------- */
function closeInspector() { $('#inspector').hidden = true; }
function inspector(it) {
  if (!it) return closeInspector();
  const p = local(it), I = $('#inspector'); I.hidden = false;
  const conf = it.confidence || 'unknown', f = it.focus, fc = it.faces;
  I.innerHTML = `${thumbOf(it) ? `<button class="preview" aria-label="${esc(it.filename)}"><img alt="" src="${thumbOf(it)}"></button>` : ''}
    <h3>${esc(it.filename)}</h3>
    <div class="acts">
      <button class="btn small" data-a="fav" aria-pressed="${!!it.favorite}">${icon('heart', it.favorite ? 'style="fill:var(--heart);stroke:var(--heart)"' : '')}${esc(it.favorite ? t('unfavorite') : t('favorite'))}</button>
      <button class="btn small ${it.rejected ? '' : 'danger'}" data-a="rej">${icon(it.rejected ? 'check' : 'xmark')}${esc(it.rejected ? t('restore') : t('reject'))}</button>
    </div>
    <dl>
      <dt>${esc(t('captureTime'))}</dt><dd>${esc(p.day)} ${esc(p.time)} ${esc(fmtOffset(it.offset_minutes))} <span class="pill ${esc(conf)}">${esc(t('confText')[conf] || conf)}</span></dd>
      ${it.clock_correction_s ? `<dt>${esc(t('clockFix'))}</dt><dd>${esc(fmtSec(it.clock_correction_s))}. ${esc(t('fileSays'))} ${esc((it.local_time || '').replace('T', ' ').slice(0, 19))}</dd>` : ''}
      <dt>${esc(t('place'))}</dt><dd>${it.place ? `${esc(it.place.label)}${it.place.country ? ', ' + esc(it.place.country) : ''}<br><span class="hint">${esc(t('fromGps'))}, ${esc(it.place.distance_km)} ${esc(t('kmFrom'))}</span>` : esc(t('unknownNoGps'))}</dd>
      <dt>${esc(t('source'))}</dt><dd><span class="dot" style="background:${lane(it.source_id)}"></span> ${esc(it.owner)}</dd>
      <dt>${esc(t('device'))}</dt><dd>${esc(it.device)}</dd>
      <dt>${esc(t('size'))}</dt><dd>${it.width && it.height ? esc(it.width + ' × ' + it.height) : '?'}${it.duration ? ', ' + esc(fmtDur(it.duration)) : ''}</dd>
      ${fc ? `<dt>${esc(t('faces'))}</dt><dd>${fc.faces} · <span class="pill ${fc.eyes_closed ? 'warn' : 'ok'}">${esc(fc.eyes_closed ? t('eyesClosed') : t('eyesOpen'))}</span> <span class="pill ${fc.looking_away ? 'warn' : 'ok'}">${esc(fc.looking_away ? t('lookAway') : t('lookingCam'))}</span></dd>` : ''}
      ${f ? `<dt>${esc(t('focus'))}</dt><dd><span class="seg" role="group" aria-label="${esc(t('focus'))}">${[[null, 'auto'], ['sharp', 'sharp'], ['soft', 'soft'], ['blurry', 'blurry']].map(([v, k]) => `<button data-focus="${v ?? ''}" aria-pressed="${(f.override ?? null) === v}">${esc(t(k))}</button>`).join('')}</span></dd>` : ''}
      <dt>${esc(t('file'))}</dt><dd class="hint" style="word-break:break-all">${esc(it.path)}</dd>
    </dl>
    ${it.ai ? `<section><div class="hint">${esc(t('aiDesc'))}</div><p style="margin:4px 0">${esc(it.ai.description || '')}</p>
      <div style="display:flex;gap:4px;flex-wrap:wrap">${(it.ai.tags || []).map(x => `<span class="chip">${esc(x)}</span>`).join('')}</div>
      ${it.ai.text_visible ? `<p class="hint">${esc(t('textInPhoto'))}: ${esc(it.ai.text_visible)}</p>` : ''}</section>` : ''}
    <section style="display:flex;flex-direction:column;gap:8px;align-items:flex-start">
      ${it.kind === 'image' ? `<label style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="wpBox" ${it.wallpaper ? 'checked' : ''}>${icon('phone')} ${esc(t('wallpaper'))}</label>` : ''}
      ${it.event_id ? `<button class="link" id="splitBtn">${esc(t('splitHere'))}</button>` : ''}</section>
    ${it.notes?.length ? `<details class="more"><summary class="hint">${esc(t('howTime'))}</summary><ul style="margin:4px 0;padding-left:18px;font-size:12px">${it.notes.map(n => `<li>${esc(n)}</li>`).join('')}</ul></details>` : ''}
    ${S.view === 'best' && it.scores ? `<section><div class="bars">${['aesthetic', 'composition', 'technical', 'sharpness', 'color'].map(c => `<span>${esc(t(c))}</span><span class="track"><i style="width:${it.scores[c]}%"></i></span><span>${it.scores[c]}</span>`).join('')}</div></section>` : ''}`;
  I.querySelector('[data-a=fav]').onclick = () => markMany([it], {favorite: !it.favorite});
  I.querySelector('[data-a=rej]').onclick = () => markMany([it], {rejected: !it.rejected});
  I.querySelectorAll('[data-focus]').forEach(b => { b.onclick = () => markMany([it], {focus: b.dataset.focus || null}); });
  const wp = I.querySelector('#wpBox'); if (wp) wp.onchange = e => markMany([it], {wallpaper: e.target.checked});
  const sp = I.querySelector('#splitBtn'); if (sp) sp.onclick = () => eventAction('/events/split', {asset_id: it.id});
  const pv = I.querySelector('.preview'); if (pv) pv.onclick = () => quickLook(it);
}

/* ---------- quick look ---------- */
function quickLook(it) {
  it = it || S.list[S.cursor]; if (!it) return;
  const q = $('#quicklook'), img = q.querySelector('img'), vid = q.querySelector('video'); q.hidden = false;
  if (it.kind === 'video') { img.hidden = true; vid.hidden = false; vid.src = `/api/collections/${S.cid}/media/${it.id}`; }
  else { vid.hidden = true; vid.pause(); vid.removeAttribute('src'); img.hidden = false; img.src = `/api/image?path=${encodeURIComponent(it.path)}`; }
  const p = local(it);
  q.querySelector('.qlbar').innerHTML = `<span>${esc(it.filename)} · ${esc(p.day)} ${esc(p.time)} · ${esc(it.owner)}</span>${it.favorite ? icon('heart', 'style="fill:var(--heart);stroke:var(--heart)"') : ''}<kbd>Esc</kbd>`;
}
function closeQL() { const q = $('#quicklook'); q.hidden = true; q.querySelector('img').removeAttribute('src'); const v = q.querySelector('video'); v.pause(); v.removeAttribute('src'); }
$('#quicklook').onclick = e => { if (e.target.tagName !== 'VIDEO') closeQL(); };

/* ---------- step 1: photos and people ---------- */
function viewImport() {
  const srcs = S.data?.sources || [];
  $('#main').innerHTML = `<div class="card">${srcs.map(s => `<div class="person">
      <span class="dot" style="background:${lane(s.id)}"></span><input type="text" value="${esc(s.owner)}" data-owner="${s.id}" aria-label="${esc(t('personName'))}">
      <span class="path" title="${esc(s.path)}">${icon('folder')} ${esc(s.path)}</span><span class="hint">${s.assets ?? ''} ${esc(t('files_'))}</span></div>`).join('')}
    <div class="person"><span class="dot" style="background:${LANES[srcs.length % LANES.length]}"></span><input type="text" id="pName" placeholder="${esc(t('personName'))}" aria-label="${esc(t('personName'))}">
      <span class="path"></span><button class="btn small" id="pAdd">${icon('folder')}${esc(t('chooseFolder'))}</button></div></div>`;
  document.querySelectorAll('[data-owner]').forEach(i => { i.onchange = () => api(`/api/collections/${S.cid}/sources/${i.dataset.owner}`, {method: 'PATCH', body: JSON.stringify({owner: i.value})}).then(reload); });
  $('#pAdd').onclick = async () => {
    const owner = $('#pName').value.trim(); if (!owner) { status(t('personName') + '?', true); return $('#pName').focus(); }
    status(t('chooseDialog'));
    const r = await post(`/api/collections/${S.cid}/sources`, {owner, browse: true});
    if (r.cancelled) return status(t('cancelled')); if (r.error) return status(r.error, true);
    await post(`/api/collections/${S.cid}/index`); await reload(); checkJob();
  };
}

/* ---------- wizard (sheet) ---------- */
function openWizard() {
  const people = [{name: t('person1'), path: ''}, {name: t('person2'), path: ''}];
  const sh = $('#sheet'); sheetOpened(); sh.hidden = false;
  const close = () => { sh.hidden = true; sh.innerHTML = ''; sheetClosed(); };
  let name = '';
  const draw = () => {
    sh.innerHTML = `<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="wzT"><h2 id="wzT">${esc(t('wizardTitle'))}</h2>
      <p class="hint" style="margin:0 0 16px">${esc(t('wizardLead'))}</p>
      <label class="lbl-top" for="wzName">${esc(t('tripName'))}</label><input type="text" id="wzName" value="${esc(name)}" placeholder="${esc(t('tripNamePh'))}" style="width:100%">
      ${people.map((p, i) => `<div class="person"><span class="dot" style="background:${LANES[i % LANES.length]}"></span>
        <input type="text" data-pn="${i}" value="${esc(p.name)}" aria-label="${esc(t('personName'))} ${i + 1}">
        <span class="path" title="${esc(p.path)}">${p.path ? esc(p.path) : ''}</span>
        <button class="btn small" data-pf="${i}">${icon('folder')}${esc(p.path ? '…' : t('chooseFolder'))}</button></div>`).join('')}
      <button class="link" id="wzMore" style="margin-top:10px">${icon('plus')}${esc(t('addFolder'))}</button>
      <div id="wzErr" class="status bad" role="alert" style="margin-top:8px"></div>
      <div class="foot"><button class="btn" id="wzCancel">${esc(t('cancel'))}</button><button class="btn primary" id="wzGo">${esc(t('create'))}</button></div></div>`;
    $('#wzName').oninput = e => { name = e.target.value; };
    sh.querySelectorAll('[data-pn]').forEach(i => { i.oninput = () => { people[+i.dataset.pn].name = i.value; }; });
    sh.querySelectorAll('[data-pf]').forEach(b => { b.onclick = async () => {
      const r = await post('/api/browse-folder', {prompt: `${people[+b.dataset.pf].name || t('personName')}: ${t('chooseFolder')}`});
      if (r.path) { people[+b.dataset.pf].path = r.path; draw(); }
    }; });
    $('#wzMore').onclick = () => { people.push({name: '', path: ''}); draw(); sh.querySelector(`[data-pn="${people.length - 1}"]`).focus(); };
    $('#wzCancel').onclick = close;
    $('#wzName').onkeydown = e => { if (e.key === 'Enter') $('#wzGo').click(); };
    $('#wzGo').onclick = async () => {
      const chosen = people.filter(p => p.path), err = $('#wzErr');
      if (!name.trim()) { err.textContent = t('needName'); return $('#wzName').focus(); }
      if (!chosen.length) { err.textContent = t('needFolder'); return; }
      $('#wzGo').disabled = true;
      const c = await post('/api/collections', {name: name.trim()});
      if (c.error) { $('#wzGo').disabled = false; err.textContent = c.error; return; }
      for (const p of chosen) {
        const r = await post(`/api/collections/${c.id}/sources`, {owner: p.name.trim() || '?', path: p.path});
        if (r.error) { $('#wzGo').disabled = false; err.textContent = `${p.path}: ${r.error}`; return; }
      }
      await post(`/api/collections/${c.id}/workflow`, {step: 'import', done: true});
      await post(`/api/collections/${c.id}/index`);
      sh.hidden = true; sh.innerHTML = ''; sheetReturn = null;
      store.set('pc-coll', c.id); store.set('pc-view:' + c.id, 's_times');
      await loadTrips(c.id);
    };
    $('#wzName').focus();
  };
  draw();
  sh.onkeydown = e => { if (e.key === 'Escape') close(); };
}

/* ---------- step 2: times ---------- */
function viewTimes() {
  if (!S.clocks.length) { $('#main').innerHTML = empty('emptyIdx', 'emptyIdxHint'); return; }
  $('#main').innerHTML = `<div class="card"><h3>${esc(t('clocks'))}</h3>${S.clocks.map(c => {
    const e = c.evidence || {}, sug = c.suggested_s != null && !['accepted', 'manual'].includes(c.status);
    const note = c.status === 'reference' ? t('reference') : c.status === 'rejected' ? t('rejectedS') : (e.note || t('notAnalysed'));
    return `<div class="clock"><div class="clock-h"><span class="dot" style="background:${lane(c.source_id)}"></span><b>${esc(c.owner)}</b><span class="hint">${esc(c.device)}</span><span class="hint" style="margin-left:auto">${c.photos} ${esc(t('photosN'))}</span></div>
      <div class="hint clock-n">${esc(note)}${c.applied_s ? ` <b style="color:var(--accent)">${esc(fmtSec(c.applied_s))} ${esc(t('applied'))}</b>` : ''}</div>
      <div class="clock-a">${sug ? `<button class="btn small primary" data-ca="accept" data-c="${c.clock_id}">${esc(t('apply'))} ${esc(fmtSec(c.suggested_s))}</button>` : ''}
      <input type="number" step="1" placeholder="${esc(t('seconds'))}" data-in="${c.clock_id}" style="width:110px" aria-label="${esc(c.owner)} ${esc(t('seconds'))}">
      <button class="btn small" data-ca="manual" data-c="${c.clock_id}">${esc(t('set'))}</button>
      ${c.applied_s ? `<button class="btn small" data-ca="reset" data-c="${c.clock_id}">${icon('undo')}${esc(t('undo'))}</button>` : ''}${sug ? `<button class="btn small" data-ca="reject" data-c="${c.clock_id}">${esc(t('rejectS'))}</button>` : ''}</div></div>`;
  }).join('')}</div>`;
  document.querySelectorAll('[data-ca]').forEach(b => { b.onclick = async () => {
    const body = {action: b.dataset.ca};
    if (b.dataset.ca === 'manual') { const v = document.querySelector(`[data-in="${b.dataset.c}"]`).value; if (v === '') return; body.seconds = +v; }
    const r = await post(`/api/collections/${S.cid}/clocks/${b.dataset.c}`, body); if (r.error) return status(r.error, true); reload();
  }; });
}

/* ---------- step 3: best of each moment ---------- */
function faceLine(fc) {
  if (!fc) return '';
  return `<span class="pill ${fc.eyes_closed ? 'warn' : 'ok'}">${icon('eye')} ${esc(fc.eyes_closed ? t('eyesClosed') : t('eyesOpen'))}</span>
    <span class="pill ${fc.looking_away ? 'warn' : 'ok'}">${esc(fc.looking_away ? t('lookAway') : t('lookingCam'))}</span>`;
}
function viewDuplicates() {
  const groups = S.groups = S.dups.filter(g => g.category !== 'similar_scene');
  if (!groups.length) { $('#main').innerHTML = empty('noDups', 'noDupsHint'); return; }
  S.dupG = Math.min(S.dupG, groups.length - 1);
  const byId = Object.fromEntries(S.data.items.map(i => [i.id, i]));
  const title = {exact: t('identical'), near: t('near')};
  $('#tools').innerHTML = `<span class="hint">${esc(t('dupKeys'))}</span>`;
  $('#main').innerHTML = groups.map((g, gi) => `<div class="group ${gi === S.dupG ? 'current' : ''}" data-g="${gi}">
    <h3>${esc(title[g.category] || g.category)} · ${g.members.length} ${esc(t('photosN'))}</h3>
    <div class="why">${esc((g.reasons.keeper || []).map(r => r.charAt(0).toUpperCase() + r.slice(1)).join(' · '))}</div>
    <div class="cands">${g.members.map((m, mi) => { const it = byId[m.id] || {kind: 'image', path: m.path}; return `<div class="cand ${m.id === g.keeper_id ? 'keep' : ''} ${gi === S.dupG && mi === S.dupC ? 'focus' : ''}" data-gi="${gi}" data-mi="${mi}">
      <img loading="lazy" alt="" src="${thumbOf({...it, path: m.path})}" data-qlid="${m.id}">
      <div class="body"><div>${m.id === g.keeper_id ? `<span class="pill ok">${icon('check')} ${esc(t('keep'))}</span> ` : ''}<b>${esc((m.local_time || '').slice(11, 19))}</b> · ${esc(m.owner)}</div>
      <div class="row">${faceLine(it.faces)}${it.focus ? `<span class="pill ${esc(it.focus.tier)}">${esc(t(it.focus.tier))}</span>` : ''}</div>
      <div class="hint">${m.width && m.height ? esc(m.width + ' × ' + m.height) : ''}</div>
      ${m.id !== g.keeper_id ? `<button class="btn small" data-keep="${gi}:${m.id}">${esc(t('keepThis'))}</button>` : ''}</div></div>`; }).join('')}</div>
    ${(g.reasons.keeper || [])[0] === 'chosen by you' ? `<button class="link" data-keep="${gi}:" style="margin-top:8px">${esc(t('useRec'))}</button>` : ''}</div>`).join('');
  document.querySelectorAll('[data-keep]').forEach(b => { b.onclick = e => { e.stopPropagation(); const [gi, id] = b.dataset.keep.split(':'); keeper(groups[+gi], id ? +id : null); }; });
  document.querySelectorAll('.cand').forEach(c => { c.onclick = () => { S.dupG = +c.dataset.gi; S.dupC = +c.dataset.mi; paintDup(); }; });
  document.querySelectorAll('[data-qlid]').forEach(im => { im.ondblclick = () => quickLook(byId[+im.dataset.qlid]); });
  paintDup(true);
}
function paintDup(scroll) {
  document.querySelectorAll('.group').forEach(g => g.classList.toggle('current', +g.dataset.g === S.dupG));
  document.querySelectorAll('.cand').forEach(c => c.classList.toggle('focus', +c.dataset.gi === S.dupG && +c.dataset.mi === S.dupC));
  const cur = document.querySelector('.group.current');
  if (cur && scroll !== false) cur.scrollIntoView({block: 'nearest'});
}
async function keeper(g, assetId) {
  const r = await post(`/api/collections/${S.cid}/duplicates/${g.id}/keeper`, {asset_id: assetId}); if (r.error) return status(r.error, true);
  const scroll = $('#main').scrollTop; await reload(); $('#main').scrollTop = scroll;
}

/* ---------- step 4: blurry ---------- */
function viewBlurry() {
  S.list = S.data.items.filter(i => i.focus && (i.focus.tier === 'blurry' || i.focus.auto_tier === 'blurry'));
  if (!S.list.length) { $('#main').innerHTML = empty('noBlurry', 'noBlurryHint'); return; }
  $('#tools').innerHTML = `<button class="btn small" id="rejAll">${icon('xmark')}${esc(t('leaveOutAll'))}</button><span class="hint">${esc(t('keysLib'))}</span>`;
  $('#main').innerHTML = `<div class="grid">${S.list.map((it, i) => tile(it, i)).join('')}</div>`;
  bindTiles();
  $('#rejAll').onclick = () => markMany(S.list.filter(i => !i.rejected && i.focus.tier === 'blurry' && !i.favorite), {rejected: true});
}

/* ---------- step 5: days and events ---------- */
function viewEvents() {
  const items = S.data.items, evs = {}; (S.data.events || []).forEach(e => { evs[e.id] = e; });
  S.list = items;
  $('#tools').innerHTML = `<span class="hint">${esc(t('keysLib'))}</span>`;
  let html = '', day = null, ev, first = true;
  items.forEach((it, idx) => {
    const p = local(it);
    if (p.day !== day) {
      if (day !== null) html += '</div></div></div></section>';
      day = p.day; ev = undefined; first = true;
      const n = items.filter(x => local(x).day === day).length, edited = (S.data.events || []).some(e => e.day === day && e.locked);
      html += `<section class="day"><h2>${esc(dayTitle(day))}<small>${n} ${esc(t('items'))}</small>${edited ? `<button class="link" data-reset="${esc(day)}">${esc(t('undoDay'))}</button>` : ''}</h2><div>`;
    } else if (it.event_id !== ev) html += '</div></div>';
    if (it.event_id !== ev) {
      ev = it.event_id; const E = evs[ev] || {name: '', count: 0};
      html += `<div class="event"><header><b>${esc(E.name)}</b><time>${esc(p.time.slice(0, 5))}</time><span class="hint">${E.count} ${esc(t('photosN'))}${E.name_source === 'user' ? ' · ' + esc(t('namedByYou')) : ''}</span>
        ${E.id ? `<button class="link" data-ren="${E.id}">${esc(t('rename'))}</button>` : ''}${E.id && !first ? `<button class="link" data-merge="${E.id}">${esc(t('mergePrev'))}</button>` : ''}</header><div class="grid">`;
      first = false;
    }
    html += tile(it, idx);
  });
  html += '</div></div></div></section>';
  $('#main').innerHTML = html;
  bindTiles();
  document.querySelectorAll('[data-ren]').forEach(b => { b.onclick = async () => { const cur = evs[+b.dataset.ren]; const name = await ask(t('eventName'), cur ? cur.name : ''); if (name) eventAction(`/events/${b.dataset.ren}`, {action: 'rename', name}); }; });
  document.querySelectorAll('[data-merge]').forEach(b => { b.onclick = () => eventAction(`/events/${b.dataset.merge}`, {action: 'merge_previous'}); });
  document.querySelectorAll('[data-reset]').forEach(b => { b.onclick = () => eventAction('/events/reset', {day: b.dataset.reset}); });
}
async function eventAction(path, body) { const r = await post(`/api/collections/${S.cid}${path}`, body); if (r.error) { status(r.error, true); return; } status(''); await reload(); }

/* ---------- step 6: descriptions ---------- */
function viewDescriptions() {
  const items = S.data.items.filter(i => i.kind === 'image'), described = items.filter(i => i.ai);
  $('#main').innerHTML = `<div class="card hero"><div class="ico">${icon('text')}</div><div style="flex:1"><h3>${described.length} / ${items.length} ${esc(t('described'))}</h3>
      <p class="hint" style="margin:0 0 10px">${esc(t('describeHint'))}</p><button class="btn primary" id="descBtn">${esc(t('describeNow'))}</button></div></div>
    <div class="grid desc">${described.slice(0, 120).map(it => `<figure class="dcard"><img loading="lazy" alt="" src="${thumbOf(it)}"><figcaption>${esc(it.ai.description || '')}</figcaption></figure>`).join('')}</div>`;
  $('#descBtn').onclick = async () => {
    if ($('#descBtn').dataset.running) { await api(`/api/collections/${S.cid}/index`, {method: 'DELETE'}); return; }
    const r = await post(`/api/collections/${S.cid}/describe`); if (r.error) return status(r.error, true); checkJob();
  };
  syncDescribeButton();
}

/* ---------- step 7: export ---------- */
function sel(id, label, opts, cur) {
  return `<div><label for="${id}">${esc(label)}</label><select class="pop" id="${id}" style="width:100%">${opts.map(([v, x]) => `<option value="${v}" ${v === cur ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select></div>`;
}
function planTable(p) {
  return `<p style="margin:14px 0 6px"><b>${p.files} ${esc(t('files'))}</b>, ${(p.bytes / 1e6).toFixed(0)} MB${p.writes_metadata ? ' · ' + esc(t('writesMeta')) : ''}</p>
    <div style="display:flex;gap:6px;flex-wrap:wrap">${Object.entries(p.warnings || {}).map(([k, n]) => `<span class="chip">${n} ${esc(tw(k))}</span>`).join('')}</div>
    <table class="plan"><thead><tr><th>${esc(t('newPath'))}</th><th>${esc(t('original'))}</th></tr></thead><tbody>${p.entries.slice(0, 300).map(e => `<tr><td>${esc(e.dest)}</td><td class="hint">${esc(e.original_name)}${e.paired_with ? ' (' + esc(t('paired')) + ')' : ''}${e.alternative ? ' (' + esc(t('alternative')) + ')' : ''}</td></tr>`).join('')}</tbody></table>
    ${p.entries.length > 300 ? `<p class="hint">${esc(t('showing'))} 300 ${esc(t('of'))} ${p.entries.length}.</p>` : ''}`;
}
function viewExport() {
  const o = S.exportOpts, p = S.plan, custom = (p && p.preset !== 'google_photos') || o.selection === 'best';
  $('#main').innerHTML = `<div class="card hero"><div class="ico">${icon('share')}</div><div style="flex:1"><h3>${esc(t('gpExport'))}</h3>
      <p class="hint" style="margin:0 0 12px">${esc(t('gpWhat'))}</p>
      <div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn" id="gpPrev">${esc(t('preview'))}</button><button class="btn primary" id="gpRun">${icon('share')}${esc(t('chooseDest'))}</button></div>
      ${p && p.preset === 'google_photos' ? planTable(p) : ''}</div></div>
    <details class="more card" ${custom ? 'open' : ''}><summary>${esc(t('custom'))}</summary><div class="form">
      ${sel('xSel', t('selection'), [['all', t('selAll')], ['no_blurry', t('selNoBlurry')], ['best', t('selBest') + ` (${o.topn})`]], o.selection)}
      ${sel('xTemplate', t('fileNames'), [['default', '2026-10-28_11-02-02_Florence_morning_001'], ['original', '20261028_110202_IMG_0581'], ['place', '2026-10-28_Florence_001'], ['trip', 'Trip_Day-6_Florence-morning_001']], o.template)}
      ${sel('xFolders', t('foldersL'), [['day', t('byDayPlace')], ['date', t('byDay')], ['event', t('byEvent')], ['place', t('byPlace')], ['flat', t('oneFolder')]], o.folders)}
      ${sel('xDups', t('dupsOpt'), [['skip', t('leaveOutOpt')], ['alternatives', t('alternatives')], ['include', t('includeToo')]], o.duplicates)}
      <div class="full" style="display:flex;gap:8px"><button class="btn" id="xPreview">${esc(t('preview'))}</button><button class="btn" id="xRun">${esc(t('chooseDest'))}</button></div></div>
      ${p && p.preset !== 'google_photos' ? planTable(p) : ''}</details>`;
  const read = () => Object.assign(S.exportOpts, {selection: $('#xSel').value, template: $('#xTemplate').value, folders: $('#xFolders').value, duplicates: $('#xDups').value});
  const preview = async body => { status(''); const r = await post(`/api/collections/${S.cid}/export/preview`, body); if (r.error) return status(r.error, true); r.preset = body.preset || 'custom'; S.plan = r; render(); };
  const run = async body => {
    status(t('chooseDialog')); const r = await post(`/api/collections/${S.cid}/export`, body);
    if (r.cancelled) return status(t('cancelled')); if (r.error) return status(r.error, true); status(t('exportStarted')); checkJob();
  };
  $('#gpPrev').onclick = () => preview({preset: 'google_photos'});
  $('#gpRun').onclick = () => run({preset: 'google_photos'});
  ['xSel', 'xTemplate', 'xFolders', 'xDups'].forEach(id => { $('#' + id).onchange = () => { read(); S.plan = null; }; });
  $('#xPreview').onclick = () => { read(); preview({...S.exportOpts}); };
  $('#xRun').onclick = () => { read(); run({...S.exportOpts}); };
}

/* ---------- browse: all photos ---------- */
function sortList(list) {
  const q = it => (it.favorite ? 100 : 0) + (it.focus ? ({sharp: 2, soft: 1, blurry: 0})[it.focus.tier] * 10 : 10) + (it.faces ? it.faces.score : 0.5);
  if (S.sort === 'person') return [...list].sort((a, b) => sourceIndex(a.source_id) - sourceIndex(b.source_id));
  if (S.sort === 'place') return [...list].sort((a, b) => (a.place?.label || '~').localeCompare(b.place?.label || '~'));
  if (S.sort === 'quality') return [...list].sort((a, b) => q(b) - q(a));
  return list;
}
function viewLibrary() {
  const f = S.filter, srcs = S.data.sources || [];
  const seg = (key, label, opts) => `<span class="seg" role="group" aria-label="${esc(label)}">${opts.map(([v, txt]) => `<button data-f="${key}" data-val="${v}" aria-pressed="${f[key] === v}">${txt}</button>`).join('')}</span>`;
  $('#tools').innerHTML = seg('state', t('all'), [['all', esc(t('all'))], ['fav', icon('heart') + esc(t('favorites'))], ['rej', esc(t('rejected'))], ['video', esc(t('videos'))]])
    + seg('focus', t('focus'), [['all', esc(t('all'))], ['sharp', esc(t('sharp'))], ['soft', esc(t('soft'))], ['blurry', esc(t('blurry'))]])
    + (srcs.length > 1 ? seg('source', t('source'), [['all', esc(t('all'))], ...srcs.map(s => [String(s.id), `<span class="dot" style="background:${lane(s.id)}"></span>${esc(s.owner)}`])]) : '')
    + `<span class="spacer"></span><label class="hint" for="sortSel">${esc(t('sort'))}</label><select class="pop" id="sortSel">${[['time', 's_time'], ['person', 's_person'], ['place', 's_place'], ['quality', 's_quality']].map(([v, k]) => `<option value="${v}" ${S.sort === v ? 'selected' : ''}>${esc(t(k))}</option>`).join('')}</select>`;
  document.querySelectorAll('[data-f]').forEach(b => { b.onclick = () => { S.filter[b.dataset.f] = b.dataset.val; S.sel.clear(); closeInspector(); render(); }; });
  $('#sortSel').onchange = e => { S.sort = e.target.value; S.sel.clear(); render(); };
  S.list = sortList(S.data.items.filter(it => (f.state === 'all' ? !it.rejected : f.state === 'fav' ? it.favorite : f.state === 'rej' ? it.rejected : it.kind === 'video')
    && (f.focus === 'all' || it.focus?.tier === f.focus) && (f.source === 'all' || String(it.source_id) === f.source)));
  $('#main').innerHTML = S.list.length ? `<div class="grid">${S.list.map((it, i) => tile(it, i)).join('')}</div>` : `<div class="empty"><p>${esc(t('noMatch'))}</p></div>`;
  bindTiles();
}

/* ---------- browse: best ---------- */
const CATS = ['aesthetic', 'composition', 'technical', 'sharpness', 'color'];
async function viewBest() {
  const d = await api(`/api/collections/${S.cid}/best?topn=${S.exportOpts.topn}`), w = d.weights;
  if (S.view !== 'best') return;
  const byId = Object.fromEntries(S.data.items.map(i => [i.id, i]));
  S.list = (d.photos || []).filter(b => byId[b.id]).map(b => ({...byId[b.id], rank: b.rank, score: b.score, scores: b.scores}));
  $('#tools').hidden = false;
  $('#tools').innerHTML = `<button class="btn small" id="toExport">${icon('share')}${esc(t('exportThese'))}</button><button class="btn small" id="wpExport">${icon('phone')}${esc(t('exportWall'))}</button>`;
  $('#main').innerHTML = `<details class="card more"><summary>${esc(t('weights'))}</summary><div class="weights">${CATS.map(c => `<label for="w-${c}">${esc(t(c))}</label>
      <input type="range" id="w-${c}" min="0" max="50" value="${w[c]}"><span id="wv-${c}">${w[c]}</span>`).join('')}
      <label for="topn">${esc(t('topN'))}</label><input type="number" id="topn" min="1" max="2000" value="${S.exportOpts.topn}" style="width:90px"><button class="link" id="resetW">${esc(t('resetWeights'))}</button></div>
      <p class="hint">${esc(t('bestHint'))}</p></details>
    <div class="grid">${S.list.map((it, i) => tile(it, i, `<span class="bd">#${it.rank}</span>`)).join('')}</div>`;
  bindTiles();
  CATS.forEach(c => { const el = $(`#w-${c}`); el.oninput = () => { $(`#wv-${c}`).textContent = el.value; };
    el.onchange = async () => { const nw = {}; CATS.forEach(k => { nw[k] = +$(`#w-${k}`).value; }); await post('/api/settings', {rank_weights: nw}); viewBest(); }; });
  $('#topn').onchange = () => { S.exportOpts.topn = Math.max(1, +$('#topn').value || 50); viewBest(); };
  $('#resetW').onclick = async () => { await post('/api/settings', {rank_weights: {aesthetic: 30, composition: 22, technical: 20, sharpness: 16, color: 12}}); viewBest(); };
  $('#toExport').onclick = () => { S.exportOpts.selection = 'best'; S.plan = null; go('s_export'); };
  $('#wpExport').onclick = async () => {
    status(t('chooseDialog')); const r = await post(`/api/collections/${S.cid}/export/wallpapers`, {});
    if (r.cancelled) return status(t('cancelled')); if (r.error) return status(r.error, true); checkJob();
  };
}

/* ---------- browse: search ---------- */
$('#searchForm').onsubmit = async e => {
  e.preventDefault(); const q = $('#q').value.trim(); if (!q || !S.cid) return;
  status(t('searching'));
  S.searchRes = await api(`/api/collections/${S.cid}/search?q=${encodeURIComponent(q)}`);
  status(S.searchRes.error || '', !!S.searchRes.error); go('search');
};
function viewSearch() {
  const r = S.searchRes || {}; if (r.error) { $('#main').innerHTML = `<div class="empty"><p>${esc(r.error)}</p></div>`; return; }
  const byId = Object.fromEntries(S.data.items.map(i => [i.id, i]));
  const res = (r.results || []).filter(x => byId[x.id]);
  S.list = res.map(x => byId[x.id]);
  $('#tools').innerHTML = `<span class="hint">${res.length} ${esc(t('bestOf'))} “${esc(r.query)}”${r.english ? ` · ${esc(t('alsoAs'))} “${esc(r.english)}”` : ''} · ${esc(t('simGuess'))}</span>`;
  $('#main').innerHTML = `<div class="grid">${S.list.map((it, i) => tile(it, i, res[i].place_match ? `<span class="bd">${esc(t('placeMatch'))}</span>` : res[i].tag_match ? `<span class="bd">${esc(t('tagMatch'))}</span>` : '')).join('')}</div>`;
  bindTiles();
}

/* ---------- settings ---------- */
async function viewSettings() {
  const s = S.settings, ai = await api('/api/ai/status'), kw = s.keeper_weights || {faces: 40, focus: 30, look: 20, resolution: 10};
  if (S.view !== 'settings') return;
  const KW = ['faces', 'focus', 'look', 'resolution'];
  $('#main').innerHTML = `<div class="card"><div class="form">
      ${sel('setLang', t('language'), [['en', 'English'], ['sl', 'Slovenščina']], s.ui_language || 'en')}
      ${sel('setGpu', t('aiLimit'), [['25', t('gentle')], ['30', t('def30')], ['50', t('faster')], ['100', t('noLimit')]], String(s.ai_gpu_share ?? 30))}
      <div class="full"><label style="display:flex;gap:6px;align-items:center;color:var(--text)"><input type="checkbox" id="setBat" ${s.ai_pause_on_battery ? 'checked' : ''}> ${esc(t('pauseBattery'))}</label></div></div></div>
    <div class="card"><h3>${esc(t('keeperW'))}</h3><div class="weights">${KW.map(k => `<label for="kw-${k}">${esc(t('w_' + k))}</label><input type="range" id="kw-${k}" min="0" max="100" value="${kw[k]}"><span id="kwv-${k}">${kw[k]}</span>`).join('')}</div></div>
    <div class="card"><h3>${esc(t('aiModels'))}</h3><dl class="kv">
      <dt>${esc(t('searchModel'))}</dt><dd>${esc(ai.search_model)}: ${esc(ai.search_ready ? t('ready') : t('missing'))}</dd>
      <dt>${esc(t('descModel'))}</dt><dd>${esc(ai.vlm?.model)}: ${esc(ai.vlm?.running ? t('running') : t('notRunning'))}</dd>
      <dt>${esc(t('facesModel'))}</dt><dd>Apple Vision: ${esc(ai.faces_ready ? t('ready') : t('missing'))}</dd></dl></div>
    <div class="card"><h3>${esc(t('keysTitle'))}</h3><p class="hint" style="margin:0">${esc(t('keysLib'))}<br>${esc(t('dupKeys'))}</p></div>`;
  const save = async () => {
    const r = await post('/api/settings', {ui_language: $('#setLang').value, ai_gpu_share: +$('#setGpu').value, ai_pause_on_battery: $('#setBat').checked});
    if (r.error) return status(r.error, true);
    const changed = lang !== r.settings.ui_language; S.settings = r.settings; lang = S.settings.ui_language;
    document.documentElement.lang = lang; status(t('saved')); if (changed) { applyStatic(); render(); }
  };
  ['setLang', 'setGpu', 'setBat'].forEach(id => { $('#' + id).onchange = save; });
  KW.forEach(k => { const el = $(`#kw-${k}`); el.oninput = () => { $(`#kwv-${k}`).textContent = el.value; };
    el.onchange = async () => { const v = {}; KW.forEach(x => { v[x] = +$(`#kw-${x}`).value; });
      const r = await post('/api/settings', {keeper_weights: v}); if (r.error) return status(r.error, true);
      S.settings = r.settings; status(t('saved')); }; });
}

/* ---------- jobs ---------- */
$('#indexBtn').onclick = async () => { if (!S.cid) return; const r = await post(`/api/collections/${S.cid}/index`); if (r.error) return status(r.error, true); checkJob(); };
let lastJob = {};
function syncDescribeButton() {
  const db = $('#descBtn'); if (!db) return;
  const j = lastJob, desc = j.running && /describ|local AI/i.test(j.status || '');
  db.textContent = desc ? t('stopDescribe') : t('describeNow');
  if (desc) db.dataset.running = '1'; else delete db.dataset.running;
  db.disabled = !!j.running && !desc;
}
async function checkJob() {
  clearTimeout(S.polling); if (!S.cid) return;
  const j = lastJob = await api(`/api/collections/${S.cid}/index`);
  if (j.collection && j.collection !== S.cid && !j.running) { $('#fill').style.width = '0'; return; }
  $('#fill').style.width = (j.progress || 0) + '%'; status(j.status || '', !!j.error);
  $('#indexBtn').disabled = !!j.running;
  syncDescribeButton();
  if (j.running) S.polling = setTimeout(checkJob, 700);
  else if (j.result && S._wasRunning) { reload(); exportFinished(j.result.export); }
  S._wasRunning = !!j.running;
}

function exportFinished(x) {
  if (!x || !x.dest) return;
  if (x.ok && S.cid) post(`/api/collections/${S.cid}/workflow`, {step: 'export', done: true}).then(() => { S.wf.export = true; renderNav(); });
  const el = $('#toast'); el.hidden = false; clearTimeout(toastTimer);
  el.innerHTML = `<span>${esc(x.ok ? t('exportDone') : t('exportFailed'))}</span><button class="link" id="reveal">${esc(t('showInFinder'))}</button><button class="link" id="toastX" aria-label="${esc(t('close'))}">${icon('xmark')}</button>`;
  $('#reveal').onclick = () => post('/api/reveal-export', {path: x.dest});
  $('#toastX').onclick = () => { el.hidden = true; };
}

/* ---------- zoom and keyboard ---------- */
function setZoom() { document.documentElement.style.setProperty('--tile', $('#zoom').value + 'px'); store.set('pc-zoom', $('#zoom').value); }
$('#zoom').oninput = setZoom;
const gridColumns = () => { const g = document.querySelector('#main .grid'); return g ? getComputedStyle(g).gridTemplateColumns.split(' ').length : 1; };
document.addEventListener('keydown', e => {
  if (!$('#sheet').hidden) return;
  const tag = document.activeElement?.tagName;
  if (['INPUT', 'SELECT', 'TEXTAREA'].includes(tag)) return;
  const ql = !$('#quicklook').hidden;
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); return undoLast(); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') { e.preventDefault(); return $('#q').focus(); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'a' && S.list.length) { e.preventDefault(); S.sel = new Set(S.list.map((_, i) => i)); return paintSelection(); }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'Escape') { if (ql) closeQL(); else if (S.sel.size) { S.sel.clear(); paintSelection(); } return; }
  if (S.view === 's_duplicates') {
    const groups = S.groups, g = groups[S.dupG]; if (!g) return;
    const k = e.key;
    if (k === 'ArrowDown' || k === 'ArrowUp') { e.preventDefault(); S.dupG = Math.max(0, Math.min(groups.length - 1, S.dupG + (k === 'ArrowDown' ? 1 : -1))); S.dupC = 0; paintDup(); }
    else if (k === 'ArrowRight' || k === 'ArrowLeft') { e.preventDefault(); S.dupC = Math.max(0, Math.min(g.members.length - 1, S.dupC + (k === 'ArrowRight' ? 1 : -1))); paintDup(); }
    if (ql && /Arrow/.test(k)) quickLook(S.data.items.find(i => i.id === groups[S.dupG].members[S.dupC].id));
    if (k === ' ') { e.preventDefault(); if (ql) closeQL(); else quickLook(S.data.items.find(i => i.id === g.members[S.dupC].id)); }
    if (k === 'k' || k === 'K') keeper(g, g.members[S.dupC].id);
    return;
  }
  if (!S.list.length || !GRID_VIEWS.includes(S.view)) return;
  const cols = gridColumns(), it = S.list[S.cursor];
  const move = d => {
    e.preventDefault(); const i = Math.max(0, Math.min(S.list.length - 1, S.cursor < 0 ? 0 : S.cursor + d));
    if (e.shiftKey) { S.sel.add(i); S.cursor = i; paintSelection(); } else clickTile(i);
    if (ql) quickLook();
  };
  if (e.key === 'ArrowRight') return move(1);
  if (e.key === 'ArrowLeft') return move(-1);
  if (e.key === 'ArrowDown') return move(ql ? 1 : cols);
  if (e.key === 'ArrowUp') return move(ql ? -1 : -cols);
  if (e.key === ' ') { e.preventDefault(); return ql ? closeQL() : quickLook(); }
  const targets = S.sel.size ? selected() : (it ? [it] : []);
  if (!targets.length) return;
  const k = e.key.toLowerCase();
  if (k === 'f') markMany(targets, {favorite: !targets.every(x => x.favorite)});
  else if (k === 'x') markMany(targets, {rejected: !targets.every(x => x.rejected)});
  else if (k === 'b') markMany(targets.filter(x => x.kind === 'image'), {wallpaper: !targets.every(x => x.wallpaper)});
  else if (k === '1') markMany(targets, {focus: 'sharp'});
  else if (k === '2') markMany(targets, {focus: 'soft'});
  else if (k === '3') markMany(targets, {focus: 'blurry'});
  else if (k === '0') markMany(targets, {focus: null});
});
boot();
