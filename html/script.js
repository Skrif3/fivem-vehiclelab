'use strict';

const $ = (id) => document.getElementById(id);
const app = $('app');
const tabs = [...document.querySelectorAll('.tab')];
let catalogue = [];
let state = { revision: -1, hasVehicle: false, activeVehicle: null, preferences: null, history: {}, presets: [] };
let selectedModel = null;
let selectedBodyType = null;
let bodyPreviewIndex = null;
let bodyConfirmed = new Map();
let selectedPreset = null;
let activeTab = 0;
let screenshotActive = false;
let filtersInitialized = false;
let cameraActive = false;
let cameraPreset = 0;
let spawnLoading = false;
const cameraPresets = ['general', 'front_bumper', 'rear_bumper', 'wheels', 'roof'];
const utilityState = { frozen: false, engine: true, locked: false, doors: {} };
const pending = new Set();
const timers = new Map();
const stanceControllers = new Map();
const stanceCameraFocused = new Set();
const stanceSummaryValues = {};
let stancePrecision = 'normal';
let stanceRangeMode = 'safe';
let stanceExtendedConfirmed = false;
let stanceRequestSequence = 0;
let stancePrecisionInitialized = false;

async function post(name, data = {}) {
    const scope = data.group === 'stance'
        ? `${data.group}:${data.control || data.action || data.operation || ''}:${data.wheel || ''}:${data.phase || ''}:${data.sequence ?? ''}`
        : data.group || data.operation || data.model || '';
    const key = `${name}:${scope}`;
    if (pending.has(key)) return { success: false, error: 'That request is already running.' };
    pending.add(key);
    try {
        const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data)
        });
        if (!response.ok) throw new Error(`NUI request failed (${response.status})`);
        const result = await response.json();
        if (result.state) updateState(result.state);
        if (result.message) toast(result.message, result.success ? 'success' : 'error');
        if (!result.success && result.error) toast(result.error, 'error');
        return result;
    } catch (error) {
        toast(error.message || 'NUI request failed.', 'error');
        return { success: false, error: error.message };
    } finally { pending.delete(key); }
}

function toast(message, type = 'information') {
    if (!message) return;
    const node = document.createElement('div');
    node.className = `toast ${type}`;
    node.textContent = message;
    $('toastArea').appendChild(node);
    window.setTimeout(() => node.remove(), 3800);
}

function copyText(value) {
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(value);
    const area = document.createElement('textarea');
    area.value = value; area.style.position = 'fixed'; area.style.opacity = '0';
    document.body.appendChild(area); area.select();
    const copied = document.execCommand('copy'); area.remove();
    if (!copied) throw new Error('Clipboard access was denied.');
    return Promise.resolve();
}

function setVisible(visible) {
    app.hidden = !visible;
    app.setAttribute('aria-hidden', String(!visible));
    if (!visible) { screenshotActive = false; app.style.visibility = ''; }
}

// The NUI document exists as a full-screen surface before Lua is ready. Keep
// its only visual root closed until an explicit `open` message arrives.
setVisible(false);

function switchTab(index) {
    activeTab = (index + tabs.length) % tabs.length;
    tabs.forEach((tab, i) => tab.classList.toggle('is-active', i === activeTab));
    document.querySelectorAll('.tab-panel').forEach((panel) => panel.classList.toggle('is-active', panel.dataset.panel === tabs[activeTab].dataset.tab));
    if (tabs[activeTab].dataset.tab === 'diagnostics') renderDiagnostics();
}
tabs.forEach((tab, index) => tab.addEventListener('click', () => switchTab(index)));

function option(select, value, text) {
    const node = document.createElement('option'); node.value = String(value); node.textContent = text; select.appendChild(node); return node;
}

function favourites() { return new Set(state.preferences?.favorites || []); }
function recents() { return state.preferences?.recents || []; }

function populateFilterOptions() {
    const source = $('sourceFilter'), cls = $('classFilter');
    const previousSource = source.value, previousClass = cls.value;
    source.replaceChildren(); option(source, 'all', 'All resources');
    [...new Set(catalogue.map((v) => v.resource || 'Base Game'))].sort().forEach((value) => option(source, value, value));
    cls.replaceChildren(); option(cls, 'all', 'All classes');
    [...new Set(catalogue.map((v) => v.vehicleClass).filter(Number.isInteger))].sort((a, b) => a - b).forEach((value) => option(cls, value, `Class ${value}`));
    source.value = [...source.options].some((o) => o.value === previousSource) ? previousSource : 'all';
    cls.value = [...cls.options].some((o) => o.value === previousClass) ? previousClass : 'all';
}

function filteredVehicles() {
    const search = $('vehicleSearch').value.trim().toLowerCase();
    const type = $('typeFilter').value, source = $('sourceFilter').value, cls = $('classFilter').value;
    const favorite = favourites(), recent = new Set(recents());
    return catalogue.filter((vehicle) => {
        const haystack = [vehicle.label, vehicle.model, vehicle.manufacturer, vehicle.resource].filter(Boolean).join(' ').toLowerCase();
        if (search && !haystack.includes(search)) return false;
        if (type === 'base' && vehicle.sourceType !== 'base') return false;
        if (type === 'addon' && vehicle.sourceType !== 'addon' && vehicle.sourceType !== 'manual') return false;
        if (type === 'favorites' && !favorite.has(vehicle.model)) return false;
        if (type === 'recent' && !recent.has(vehicle.model)) return false;
        if (source !== 'all' && vehicle.resource !== source) return false;
        if (cls !== 'all' && String(vehicle.vehicleClass) !== cls) return false;
        return true;
    }).sort((a, b) => type === 'recent' ? recents().indexOf(a.model) - recents().indexOf(b.model) : (a.label || a.model).localeCompare(b.label || b.model));
}

function renderVehicles() {
    const list = $('vehicleList'), vehicles = filteredVehicles(), favorite = favourites();
    $('vehicleCount').textContent = `${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'}`;
    const fragment = document.createDocumentFragment();
    vehicles.forEach((vehicle) => {
        const row = document.createElement('button'); row.type = 'button'; row.className = `list-row${selectedModel === vehicle.model ? ' is-selected' : ''}`; row.setAttribute('role', 'option');
        const main = document.createElement('span'); main.className = 'list-main';
        const title = document.createElement('span'); title.className = 'list-title'; title.textContent = `${favorite.has(vehicle.model) ? '[Favorite] ' : ''}${vehicle.label || vehicle.model}`;
        const detail = document.createElement('span'); detail.className = 'list-detail'; detail.textContent = `${vehicle.model} · ${vehicle.manufacturer || 'Unknown make'} · ${vehicle.resource || 'Base Game'}`;
        main.append(title, detail); const badge = document.createElement('span'); badge.className = `badge ${vehicle.sourceType === 'base' ? '' : 'addon'}`; badge.textContent = vehicle.sourceType === 'base' ? 'Base' : 'Add-on'; row.append(main, badge);
        row.addEventListener('click', () => { selectedModel = vehicle.model; $('selectedVehicle').textContent = vehicle.model; renderVehicles(); post('selectCatalogueVehicle', { model: vehicle.model }); });
        row.addEventListener('dblclick', () => spawnSelected()); fragment.appendChild(row);
    });
    if (!vehicles.length) { const empty = document.createElement('div'); empty.className = 'empty'; empty.textContent = 'No vehicles match the current filters.'; fragment.appendChild(empty); }
    list.replaceChildren(fragment);
}

function populateVehicles(values) {
    catalogue = Array.isArray(values) ? values.filter((v) => v && typeof v.model === 'string') : [];
    populateFilterOptions();
    if (!filtersInitialized && catalogue.length && state.version) updateState(state); else renderVehicles();
}

async function spawnSelected() {
    if (!selectedModel) return toast('Select a vehicle first.', 'warning');
    if (spawnLoading) return;
    setSpawnLoading(true);
    try { await post('spawnVehicle', { model: selectedModel }); }
    finally { setSpawnLoading(false); }
}

function setSpawnLoading(loading) {
    spawnLoading = loading === true;
    const button = $('spawnButton');
    button.disabled = spawnLoading;
    button.textContent = spawnLoading ? 'Spawning…' : 'Spawn Selected';
}

function controlRow(label, detail, control) {
    const row = document.createElement('div'); row.className = 'control-row';
    const text = document.createElement('div'); text.className = 'control-label';
    const strong = document.createElement('strong'); strong.textContent = label; text.appendChild(strong);
    if (detail) { const small = document.createElement('small'); small.textContent = detail; text.appendChild(small); }
    row.append(text, control); return row;
}

function bodyCategory() { return (state.body || []).find((item) => item.modType === selectedBodyType); }
function optionFor(category, index) { return category?.options?.find((item) => item.index === index) || { index, label: index === -1 ? 'Stock' : `Option ${index + 1}` }; }

function renderBody() {
    const categories = state.body || [], available = state.hasVehicle && categories.length;
    $('bodyEmpty').hidden = Boolean(available); $('bodyWorkspace').hidden = !available;
    if (!state.hasVehicle) $('bodyEmpty').textContent = 'No active vehicle.';
    else if (!categories.length) $('bodyEmpty').textContent = 'This vehicle exposes no body modification slots.';
    if (!available) return;
    if (!categories.some((item) => item.modType === selectedBodyType)) selectedBodyType = categories[0].modType;
    categories.forEach((item) => { if (!bodyConfirmed.has(item.modType)) bodyConfirmed.set(item.modType, item.current); });
    const select = $('bodyCategory'); select.replaceChildren(); categories.forEach((item) => option(select, item.modType, `${item.label} (${item.count})`)); select.value = String(selectedBodyType);
    const category = bodyCategory();
    if (bodyPreviewIndex === null || !category.options.some((item) => item.index === bodyPreviewIndex)) bodyPreviewIndex = category.current;
    const confirmed = bodyConfirmed.get(category.modType);
    $('bodyCurrent').textContent = `Confirmed: ${optionFor(category, confirmed).label}`;
    $('bodyPreview').textContent = optionFor(category, bodyPreviewIndex).label;
    const pos = category.options.findIndex((item) => item.index === bodyPreviewIndex);
    $('bodyCounter').textContent = `${optionFor(category, bodyPreviewIndex).label} — ${pos + 1} / ${category.options.length}`;
}

async function previewBody(step, direct) {
    const category = bodyCategory(); if (!category) return;
    let index = direct;
    if (index === undefined) { const current = Math.max(0, category.options.findIndex((item) => item.index === bodyPreviewIndex)); index = category.options[Math.max(0, Math.min(category.options.length - 1, current + step))].index; }
    bodyPreviewIndex = index; renderBody();
    const key = `body:${category.modType}`; clearTimeout(timers.get(key));
    timers.set(key, setTimeout(() => post('advancedAction', { group: 'body', operation: 'preview', modType: category.modType, index }), 90));
}

async function confirmBody() {
    const category = bodyCategory(); if (!category) return;
    const result = await post('advancedAction', { group: 'body', operation: 'confirm', modType: category.modType, index: bodyPreviewIndex });
    if (result.success) bodyConfirmed.set(category.modType, bodyPreviewIndex);
}

function makeSelect(items, value, onChange) {
    const select = document.createElement('select'); items.forEach((item) => option(select, item.value, item.label)); select.value = String(value); select.addEventListener('change', onChange); return select;
}

function renderWheels() {
    const available = state.hasVehicle && state.capabilities;
    disposeStanceControllers();
    $('wheelsEmpty').hidden = Boolean(available); $('wheelsWorkspace').hidden = !available; if (!available) return;
    const cap = state.capabilities, setup = state.setup?.wheels || {}, modelContainer = $('wheelModelControls'), tyreContainer = $('tyreControls');
    modelContainer.replaceChildren(); tyreContainer.replaceChildren();
    const linked = document.createElement('input'); linked.type = 'checkbox'; linked.checked = true;
    const custom = document.createElement('input'); custom.type = 'checkbox'; custom.checked = setup.frontCustomTyres === true;
    const types = (cap.wheelTypes || []).map((item) => ({ value: item.id, label: `${item.label} (${item.count})` }));
    const typeSelect = makeSelect(types, setup.type, () => post('advancedAction', { group: 'wheels', operation: 'type', wheelType: Number(typeSelect.value), index: -1, customTyres: setup.frontCustomTyres === true }));
    modelContainer.appendChild(controlRow('Wheel category', 'Validated on this vehicle', typeSelect));
    const frontMod = (cap.mods || []).find((item) => item.modType === 23);
    if (frontMod) {
        const select = makeSelect(frontMod.options.map((item) => ({ value: item.index, label: item.label })), setup.front, () => post('advancedAction', { group: 'wheels', operation: 'model', axle: 'front', index: Number(select.value), customTyres: custom.checked, linked: linked.checked }));
        const search = document.createElement('input'); search.type = 'search'; search.placeholder = 'Search wheel names';
        search.addEventListener('input', () => { const query = search.value.trim().toLowerCase(), current = select.value; select.replaceChildren(); frontMod.options.filter((item) => !query || item.label.toLowerCase().includes(query)).forEach((item) => option(select, item.index, item.label)); if ([...select.options].some((item) => item.value === current)) select.value = current; });
        modelContainer.appendChild(controlRow('Wheel search', 'Filter the front wheel list', search));
        const wrap = document.createElement('div'); wrap.className = 'inline-control'; const previous = document.createElement('button'), next = document.createElement('button'); previous.type = next.type = 'button'; previous.textContent = '−'; next.textContent = '+';
        const move = (amount) => { const index = Math.max(0, select.selectedIndex + amount); select.selectedIndex = Math.min(select.options.length - 1, index); select.dispatchEvent(new Event('change')); }; previous.onclick = () => move(-1); next.onclick = () => move(1); wrap.append(previous, select, next);
        modelContainer.appendChild(controlRow('Front wheel', `${frontMod.count} options`, wrap));
    }
    const rearMod = (cap.mods || []).find((item) => item.modType === 24);
    if (rearMod) { const select = makeSelect(rearMod.options.map((item) => ({ value: item.index, label: item.label })), setup.rear, () => post('advancedAction', { group: 'wheels', operation: 'model', axle: 'rear', index: Number(select.value), customTyres: custom.checked })); modelContainer.appendChild(controlRow('Rear wheel', `${rearMod.count} options`, select)); }
    if (!frontMod && !rearMod) { const note = document.createElement('div'); note.className = 'support-note warning'; note.textContent = 'This vehicle exposes no wheel model slots.'; modelContainer.appendChild(note); }
    const toggles = document.createElement('div');
    const bullet = document.createElement('input'); bullet.type = 'checkbox'; bullet.checked = setup.bulletproof === true; bullet.addEventListener('change', () => post('advancedAction', { group: 'wheels', operation: 'bulletproof', enabled: bullet.checked }));
    [['Link front/rear', linked], ['Custom tyres', custom], ['Bulletproof tyres', bullet]].forEach(([label, input]) => { const row = document.createElement('label'); row.className = 'switch-row'; row.textContent = label; row.appendChild(input); toggles.appendChild(row); });
    if (cap.support?.driftTyres) { const drift = document.createElement('input'); drift.type = 'checkbox'; drift.checked = setup.driftTyres === true; drift.addEventListener('change', () => post('advancedAction', { group: 'wheels', operation: 'drift', enabled: drift.checked })); const row = document.createElement('label'); row.className = 'switch-row'; row.textContent = 'Drift tyres'; row.appendChild(drift); toggles.appendChild(row); }
    tyreContainer.appendChild(toggles); renderStance();
}

function disposeStanceControllers() {
    stanceControllers.forEach((controller) => { controller.disposed = true; clearTimeout(controller.timer); });
    stanceControllers.clear();
}

function stanceConfig() { return state.config?.stance || {}; }
function stanceUiConfig() { return stanceConfig().UI || {}; }
function clampNumber(value, min, max) { return Math.max(Number(min), Math.min(Number(max), Number(value))); }
function stanceStep(kind, precision = stancePrecision) { return Number(stanceUiConfig().Steps?.[precision]?.[kind]) || .01; }
function decimalsFor(step) { return Math.max(0, Math.min(4, Math.ceil(-Math.log10(Number(step) || .01)))); }
function signed(value, digits, suffix = '') { const number = Number(value) || 0; return `${number > 0 ? '+' : ''}${number.toFixed(digits)}${suffix}`; }
function stanceDirection(value, digits) { const number = Number(value) || 0; return Math.abs(number) < 1e-9 ? 'Factory position' : `${number < 0 ? 'Inward' : 'Outward'} ${Math.abs(number).toFixed(digits)}`; }

function focusStanceCamera(key, category = 'wheels') {
    if (stanceCameraFocused.has(key)) return;
    stanceCameraFocused.add(key);
    post('focusTuningCamera', { category, reset: false }).then((result) => { cameraActive = result.success || cameraActive; });
}

function updateStanceSummary(key, label, value) {
    stanceSummaryValues[key] = `${label} ${value}`;
    const values = Object.values(stanceSummaryValues);
    $('stanceSummary').textContent = values.length ? values.join('  ·  ') : 'Factory stance';
}

function makeStanceController(definition, renderValue) {
    const key = `${definition.control}:${definition.wheel || ''}`;
    const controller = {
        disposed: false, inFlight: false, pending: null, commitPending: null, timer: null,
        localValue: definition.value, lastConfirmed: definition.value, lastCommitted: null,
        lastSent: null, sequence: 0, dragging: false
    };
    stanceControllers.set(key, controller);

    const payload = (phase, displayValue) => ({
        group: 'stance', operation: 'set', phase, control: definition.control, wheel: definition.wheel,
        value: definition.toApi(displayValue), rangeMode: stanceRangeMode, sequence: (controller.sequence = ++stanceRequestSequence)
    });
    const restore = () => { if (controller.disposed) return; controller.pending = null; controller.commitPending = null; controller.localValue = controller.lastConfirmed; renderValue(controller.lastConfirmed, false); };
    const sendCommit = async (value) => {
        if (controller.disposed) return;
        controller.inFlight = true;
        controller.lastSent = value;
        const result = await post('advancedAction', payload('commit', value));
        controller.inFlight = false;
        if (controller.disposed) return;
        if (!result.success) return restore();
        controller.lastConfirmed = Number.isFinite(Number(result.actualValue)) && definition.absolute
            ? Number(result.actualValue) : definition.fromApi(Number(result.value));
        controller.lastCommitted = controller.lastConfirmed;
        renderValue(controller.lastConfirmed, false);
        if (controller.commitPending !== null || controller.pending !== null) pump();
    };
    const pump = async () => {
        if (controller.disposed || controller.inFlight) return;
        if (controller.commitPending !== null) { const value = controller.commitPending; controller.commitPending = null; controller.pending = null; return sendCommit(value); }
        if (controller.pending === null) return;
        const value = controller.pending; controller.pending = null; controller.inFlight = true;
        controller.lastSent = value;
        const result = await post('advancedAction', payload('preview', value));
        controller.inFlight = false;
        if (controller.disposed) return;
        if (!result.success) return restore();
        if (controller.commitPending !== null || controller.pending !== null) return pump();
    };
    controller.preview = (value) => {
        const next = clampNumber(value, definition.min, definition.max);
        controller.localValue = next; controller.pending = next; renderValue(next, true);
        if (!controller.timer) controller.timer = setTimeout(() => { controller.timer = null; pump(); }, clampNumber(stanceUiConfig().PreviewIntervalMs || 40, 30, 60));
    };
    controller.commit = (value = controller.localValue) => {
        const next = clampNumber(value, definition.min, definition.max);
        controller.localValue = next; renderValue(next, false); clearTimeout(controller.timer); controller.timer = null;
        if (controller.lastCommitted !== null && Math.abs(controller.lastCommitted - next) < 1e-9 && (controller.inFlight || controller.commitPending !== null)) return;
        controller.lastCommitted = next; controller.commitPending = next; controller.pending = null; pump();
    };
    return controller;
}

function stanceCard(definition) {
    const card = document.createElement('article'); card.className = 'stance-card';
    const header = document.createElement('header'), heading = document.createElement('div'), title = document.createElement('h3'), subtitle = document.createElement('small'), badge = document.createElement('span');
    title.textContent = definition.label; subtitle.textContent = definition.description; badge.className = 'stance-badge'; badge.textContent = definition.absolute ? 'Actual' : 'Relative'; heading.append(title, subtitle); header.append(heading, badge);
    const primary = document.createElement('button'); primary.type = 'button'; primary.className = 'stance-primary';
    const current = document.createElement('strong'), change = document.createElement('span'), status = document.createElement('small'); primary.append(current, change, status);
    const sliderWrap = document.createElement('div'); sliderWrap.className = 'stance-slider-wrap';
    const marker = document.createElement('i'); marker.className = 'stance-baseline-marker';
    const range = document.createElement('input'); range.type = 'range'; range.className = 'stance-slider'; range.min = definition.min; range.max = definition.max; range.step = definition.step;
    const scale = document.createElement('div'); scale.className = 'stance-scale';
    const scaleMin = document.createElement('span'), scaleFactory = document.createElement('span'), scaleMax = document.createElement('span');
    scaleMin.textContent = definition.minLabel ? `${definition.minLabel} ${definition.format(definition.min)}` : `Min ${definition.format(definition.min)}`; scaleFactory.textContent = 'Factory'; scaleMax.textContent = definition.maxLabel ? `${definition.maxLabel} ${definition.format(definition.max)}` : `Max ${definition.format(definition.max)}`; scale.append(scaleMin, scaleFactory, scaleMax);
    sliderWrap.append(range, marker, scale);
    const exact = document.createElement('div'); exact.className = 'stance-exact';
    const decrement = document.createElement('button'), increment = document.createElement('button'), number = document.createElement('input'), reset = document.createElement('button');
    decrement.type = increment.type = reset.type = 'button'; decrement.textContent = '−'; increment.textContent = '+'; reset.textContent = 'Reset';
    number.type = 'number'; number.min = definition.min; number.max = definition.max; number.step = definition.step;
    exact.append(decrement, number, increment, reset);
    const values = document.createElement('div'); values.className = 'stance-values';
    const factory = document.createElement('span'), live = document.createElement('span'), difference = document.createElement('span'); values.append(factory, live, difference);

    const renderValue = (raw, previewing) => {
        const value = clampNumber(raw, definition.min, definition.max), delta = definition.deltaFor(value), span = definition.max - definition.min || 1;
        range.value = value; number.value = Number(value).toFixed(definition.digits);
        current.textContent = definition.format(value); change.textContent = `Change ${signed(delta, definition.digits, definition.suffix)}`;
        status.textContent = previewing ? 'Live preview' : definition.directionText ? definition.directionText(delta, definition.digits) : Math.abs(delta) < 1e-9 ? 'Factory value' : 'Modified from factory';
        badge.textContent = previewing ? 'Previewing' : Math.abs(delta) < 1e-9 ? 'Factory' : 'Modified';
        factory.textContent = `Factory ${definition.format(definition.baseline)}`; live.textContent = `Current ${definition.format(value)}`; difference.textContent = `Difference ${signed(delta, definition.digits, definition.suffix)}`;
        const fill = clampNumber(((value - definition.min) / span) * 100, 0, 100), base = clampNumber(((definition.baseline - definition.min) / span) * 100, 0, 100);
        marker.style.left = `${base}%`; range.style.setProperty('--fill-start', `${definition.absolute ? 0 : Math.min(fill, base)}%`); range.style.setProperty('--fill-end', `${Math.max(fill, base)}%`);
        card.classList.toggle('is-previewing', previewing); updateStanceSummary(definition.key, definition.shortLabel, definition.format(value));
    };
    const controller = makeStanceController(definition, renderValue);
    const stepForEvent = (event) => stanceStep(definition.kind, event.altKey ? 'fine' : event.shiftKey ? 'coarse' : stancePrecision);
    const camera = () => focusStanceCamera(definition.key, definition.camera || 'wheels');
    const adjust = (amount, event = {}) => { camera(); controller.commit(controller.localValue + amount * stepForEvent(event)); };
    range.addEventListener('pointerdown', (event) => { controller.dragging = true; card.classList.add('is-dragging'); if (range.setPointerCapture) range.setPointerCapture(event.pointerId); camera(); });
    range.addEventListener('input', () => controller.preview(Number(range.value)));
    const finishRange = () => { controller.dragging = false; card.classList.remove('is-dragging'); controller.commit(Number(range.value)); };
    range.addEventListener('pointerup', finishRange); range.addEventListener('pointercancel', finishRange); range.addEventListener('mouseup', finishRange); range.addEventListener('touchend', finishRange, { passive: true }); range.addEventListener('change', finishRange);
    range.addEventListener('keydown', (event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault(); camera();
        if (event.key === 'Home') controller.preview(definition.min); else if (event.key === 'End') controller.preview(definition.max);
        else controller.preview(controller.localValue + (event.key === 'ArrowRight' ? 1 : -1) * stepForEvent(event));
    });
    range.addEventListener('keyup', (event) => { if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) controller.commit(); });
    number.addEventListener('focus', camera);
    const validExact = () => number.value.trim() !== '' && Number.isFinite(Number(number.value));
    number.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') { event.preventDefault(); if (validExact()) controller.commit(Number(number.value)); else renderValue(controller.localValue, false); number.blur(); }
        if (event.key === 'Escape') { event.preventDefault(); if (Math.abs(controller.localValue - controller.lastConfirmed) > 1e-9) controller.commit(controller.lastConfirmed); else renderValue(controller.lastConfirmed, false); number.blur(); }
        if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) {
            event.preventDefault(); camera();
            if (event.key === 'Home') controller.preview(definition.min); else if (event.key === 'End') controller.preview(definition.max);
            else controller.preview(controller.localValue + (event.key === 'ArrowRight' || event.key === 'ArrowUp' ? 1 : -1) * stepForEvent(event));
        }
    });
    number.addEventListener('keyup', (event) => { if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) controller.commit(); });
    number.addEventListener('blur', () => { if (validExact() && Math.abs(Number(number.value) - controller.localValue) > 1e-9) controller.commit(Number(number.value)); else renderValue(controller.localValue, false); });
    number.addEventListener('dblclick', () => controller.commit(definition.baseline));
    decrement.onclick = (event) => adjust(-1, event); increment.onclick = (event) => adjust(1, event); reset.onclick = () => { camera(); controller.commit(definition.baseline); }; primary.onclick = camera;
    primary.ondblclick = () => controller.commit(definition.baseline); title.ondblclick = () => controller.commit(definition.baseline);
    card.append(header, primary, sliderWrap, exact, values);
    if (definition.presets?.length) {
        const presets = document.createElement('div'); presets.className = 'stance-presets';
        definition.presets.forEach((preset) => { const button = document.createElement('button'); button.type = 'button'; button.textContent = preset.label; button.onclick = () => { camera(); controller.commit(clampNumber(definition.baseline + preset.delta, definition.min, definition.max)); }; presets.appendChild(button); });
        card.appendChild(presets);
    }
    renderValue(definition.value, false); return card;
}

function renderStance() {
    disposeStanceControllers(); Object.keys(stanceSummaryValues).forEach((key) => delete stanceSummaryValues[key]);
    const cap = state.capabilities || {}, support = cap.stance || {}, controls = state.stance?.controls || {}, config = stanceConfig(), limits = state.stance?.limits || config.Limits || {}, absoluteLimits = config.AbsoluteLimits || {}, ui = stanceUiConfig();
    app.style.setProperty('--stance-animation-ms', `${clampNumber(ui.AnimationMs || 160, 120, 200)}ms`);
    if (!stancePrecisionInitialized) { if (['fine', 'normal', 'coarse'].includes(ui.DefaultPrecision)) stancePrecision = ui.DefaultPrecision; stancePrecisionInitialized = true; }
    const sections = { dimensions: $('stanceDimensions'), position: $('stancePosition'), alignment: $('stanceAlignment'), suspension: $('stanceSuspension'), individual: $('stanceIndividual') };
    Object.values(sections).forEach((section) => section.replaceChildren());
    const definition = (options) => {
        const info = controls[options.infoKey || options.control]; if (!info) return null;
        const step = stanceStep(options.kind), baseline = options.absolute ? Number(info.baseline) : 0, value = options.absolute ? Number(info.current) : Number(info.delta);
        let deltaRange = limits[options.limitKey] || { min: -1, max: 1 };
        if (stanceRangeMode === 'extended' && ui.ExtendedLimits?.[options.limitKey]) deltaRange = ui.ExtendedLimits[options.limitKey];
        let min = options.absolute ? baseline + Number(deltaRange.min) : Number(deltaRange.min), max = options.absolute ? baseline + Number(deltaRange.max) : Number(deltaRange.max);
        const absolute = absoluteLimits[options.absoluteKey]; if (absolute) { min = Math.max(min, Number(absolute.min)); max = Math.min(max, Number(absolute.max)); }
        const digits = decimalsFor(step);
        return { ...options, key: `${options.control}:${options.wheel || ''}`, info, baseline, value, min, max, step, digits, suffix: options.suffix || '',
            format: (number) => options.signed ? signed(number, digits, options.suffix || '') : `${Number(number).toFixed(digits)}${options.suffix || ''}`,
            deltaFor: (number) => options.absolute ? Number(number) - baseline : Number(number),
            toApi: (number) => options.absolute ? Number(number) - baseline : Number(number),
            fromApi: (number) => options.absolute ? baseline + Number(number) : Number(number)
        };
    };
    const append = (section, options) => { const item = definition(options); if (item) sections[section].appendChild(stanceCard(item)); };
    if (support.wheelSize) append('dimensions', { control: 'wheelSize', label: 'Wheel Size', shortLabel: 'Size', description: 'Actual global wheel size reported by the runtime.', kind: 'wheelSize', limitKey: 'wheelSizeDelta', absoluteKey: 'wheelSize', absolute: true, presets: [
        { label: 'Factory', delta: 0 }, { label: 'Small', delta: ui.Presets?.wheelSize?.small ?? -.05 }, { label: 'Slightly Larger', delta: ui.Presets?.wheelSize?.slightlyLarger ?? .05 }, { label: 'Large', delta: ui.Presets?.wheelSize?.large ?? .15 }
    ] });
    if (support.wheelWidth) append('dimensions', { control: 'wheelWidth', label: 'Wheel Width', shortLabel: 'Width', description: 'Actual global wheel width reported by the runtime.', kind: 'wheelWidth', limitKey: 'wheelWidthDelta', absoluteKey: 'wheelWidth', absolute: true, presets: [
        { label: 'Factory', delta: 0 }, { label: 'Narrow', delta: ui.Presets?.wheelWidth?.narrow ?? -.05 }, { label: 'Slightly Wider', delta: ui.Presets?.wheelWidth?.slightlyWider ?? .05 }, { label: 'Wide', delta: ui.Presets?.wheelWidth?.wide ?? .15 }
    ] });
    if (support.axleControls) {
        append('position', { control: 'frontTrack', label: 'Front Wheel Position', shortLabel: 'Front', description: 'Front track offset · negative inward / positive outward.', kind: 'track', limitKey: 'trackDelta', signed: true, minLabel: 'More inward', maxLabel: 'More outward', directionText: stanceDirection });
        append('position', { control: 'rearTrack', label: 'Rear Wheel Position', shortLabel: 'Rear', description: 'Rear track offset · negative inward / positive outward.', kind: 'track', limitKey: 'trackDelta', signed: true, minLabel: 'More inward', maxLabel: 'More outward', directionText: stanceDirection, camera: 'rear_bumper' });
        append('alignment', { control: 'frontCamber', label: 'Front Camber', shortLabel: 'F Camber', description: 'Relative angle from the captured factory alignment.', kind: 'camber', limitKey: 'camberDegrees', suffix: '°', signed: true });
        append('alignment', { control: 'rearCamber', label: 'Rear Camber', shortLabel: 'R Camber', description: 'Relative angle from the captured factory alignment.', kind: 'camber', limitKey: 'camberDegrees', suffix: '°', signed: true, camera: 'rear_bumper' });
    }
    if (support.suspensionHeight) append('suspension', { control: 'suspensionHeight', label: 'Suspension Height', shortLabel: 'Height', description: 'Actual suspension height reported by the runtime.', kind: 'suspension', limitKey: 'suspensionHeightDelta', absoluteKey: 'suspensionHeight', absolute: true, camera: 'general' });
    const wheelNames = [['frontLeft', 'Front Left'], ['frontRight', 'Front Right'], ['rearLeft', 'Rear Left'], ['rearRight', 'Rear Right']];
    if (ui.ShowAdvancedPerWheel !== false && support.wheelOffset) wheelNames.forEach(([wheel, label]) => append('individual', { control: 'wheelOffset', infoKey: `wheelOffset:${wheel}`, wheel, label, shortLabel: label.replace(' ', ''), description: 'Independent wheel offset · negative inward / positive outward.', kind: 'track', limitKey: 'trackDelta', signed: true, minLabel: 'More inward', maxLabel: 'More outward', directionText: stanceDirection, camera: wheel.startsWith('rear') ? 'rear_bumper' : 'wheels' }));
    const setSection = (id, container) => { $(id).hidden = !container.children.length; };
    setSection('stanceDimensionsSection', sections.dimensions); setSection('stancePositionSection', sections.position); setSection('stanceAlignmentSection', sections.alignment); setSection('stanceSuspensionSection', sections.suspension); setSection('stanceAdvancedSection', sections.individual);
    $('stanceStatus').textContent = `${stanceRangeMode === 'extended' ? 'Extreme values may look incorrect on custom vehicles. ' : ''}${support.axleControls ? `Mapped ${cap.wheelMap?.mappedCount || 0} wheels using ${cap.wheelMap?.source || 'runtime mapping'}. Positive position values move wheels outward.` : `Axle controls unavailable: ${cap.wheelMap?.source || 'unsupported layout'}. Supported global controls remain available.`}`;
    $('stanceStatus').className = `support-note${support.axleControls ? '' : ' warning'}`;
    document.querySelectorAll('#stancePrecision [data-precision]').forEach((button) => { button.classList.toggle('is-active', button.dataset.precision === stancePrecision); button.onclick = () => { stancePrecision = button.dataset.precision; renderStance(); }; });
    document.querySelectorAll('#stanceRangeMode [data-range]').forEach((button) => { button.classList.toggle('is-active', button.dataset.range === stanceRangeMode); button.onclick = () => {
        const requested = button.dataset.range;
        if (requested === 'extended' && !stanceExtendedConfirmed && ui.ExtendedRangeConfirmation !== false) {
            if (!window.confirm('Extended wheel dimensions can cause clipping, instability, or visual artifacts. Enable extended ranges for this session?')) return;
            stanceExtendedConfirmed = true;
        }
        stanceRangeMode = requested; renderStance();
    }; });
    const batch = (action) => { disposeStanceControllers(); post('advancedAction', { group: 'stance', operation: 'wheelOffsetBatch', action, sequence: ++stanceRequestSequence }); };
    $('mirrorLeftToRight').onclick = () => batch('mirrorLeftToRight'); $('mirrorRightToLeft').onclick = () => batch('mirrorRightToLeft'); $('copyFrontToRear').onclick = () => batch('copyFrontToRear'); $('resetIndividualWheels').onclick = () => batch('resetIndividual');
    const mapped = state.stance?.individualWheels || {}; $('mirrorLeftToRight').disabled = !(mapped.frontLeft && mapped.frontRight) && !(mapped.rearLeft && mapped.rearRight); $('mirrorRightToLeft').disabled = $('mirrorLeftToRight').disabled; $('copyFrontToRear').disabled = !(mapped.frontLeft && mapped.frontRight && mapped.rearLeft && mapped.rearRight); $('resetIndividualWheels').disabled = !Object.keys(mapped).length;
    if (!Object.values(sections).some((section) => section.children.length)) $('stanceSummary').textContent = 'Stance controls are unsupported by this runtime.';
}

function renderPerformance() {
    const list = state.performance || [], available = state.hasVehicle && list.length; $('performanceEmpty').hidden = Boolean(available); const container = $('performanceControls'); container.replaceChildren();
    const turboSupported=(state.capabilities?.toggleMods||[]).some((item)=>item.modType===18);
    ['stockPerformance','maxPerformance','resetPerformance'].forEach((id)=>{$(id).disabled=!state.hasVehicle||!list.length;});$('toggleTurbo').disabled=!state.hasVehicle||!turboSupported;
    if (!state.hasVehicle) { $('performanceEmpty').textContent = 'No active vehicle.'; return; }
    if (!list.length) $('performanceEmpty').textContent = 'This vehicle exposes no indexed performance slots; toggle capabilities remain available below.';
    list.forEach((item) => { const select = makeSelect(item.options.map((opt) => ({ value: opt.index, label: opt.label })), state.setup?.performance?.[String(item.modType)] ?? item.current, () => post('advancedAction', { group: 'performance', operation: 'set', modType: item.modType, index: Number(select.value) })); container.appendChild(controlRow(item.label, `${item.count} available levels`, select)); });
    const turbo = document.createElement('div'); turbo.className = 'readout'; turbo.textContent = `Turbo: ${state.setup?.toggleMods?.['18'] ? 'Enabled' : 'Disabled'} · Xenon: ${state.setup?.lighting?.xenon ? 'Enabled' : 'Disabled'} · Tyre smoke: ${state.setup?.lighting?.tyreSmoke ? 'Enabled' : 'Disabled'}`; container.appendChild(turbo);
}

function rgbHex(rgb) { const c = (n) => Math.max(0, Math.min(255, Number(n) || 0)).toString(16).padStart(2, '0'); return `#${c(rgb?.r)}${c(rgb?.g)}${c(rgb?.b)}`; }
function hexRgb(hex) { const match = /^#?([0-9a-f]{6})$/i.exec(hex); if (!match) return null; const n = parseInt(match[1], 16); return { r: n >> 16, g: (n >> 8) & 255, b: n & 255 }; }

function renderPaint() {
    const available = state.hasVehicle && state.setup?.paint; $('paintEmpty').hidden = Boolean(available); $('paintWorkspace').hidden = !available;
    if (!state.hasVehicle) $('paintEmpty').textContent = 'No active vehicle.';
    else if (!available) $('paintEmpty').textContent = 'Paint state is unavailable for this vehicle.';
    if (!available) return;
    const paint = state.setup.paint, indexed = $('indexedPaint'), custom = $('customPaint'); indexed.replaceChildren(); custom.replaceChildren();
    ['primary', 'secondary'].forEach((target) => {
        const key = `${target}Index`, input = document.createElement('input'); input.type = 'number'; input.min = 0; input.max = 255; input.value = paint[key] ?? 0; input.addEventListener('change', () => post('advancedAction', { group: 'paint', operation: 'indexed', target, index: Number(input.value) })); indexed.appendChild(controlRow(`${target[0].toUpperCase()}${target.slice(1)} GTA colour`, 'Indexed palette 0–255', input));
        const type = document.createElement('select'); [['0','Normal'],['1','Metallic'],['2','Pearlescent'],['3','Matte'],['4','Metal'],['5','Chrome']].forEach(([v,l]) => option(type,v,l)); type.value = String(paint[`${target}Type`] ?? 0); type.addEventListener('change', () => post('advancedAction', { group:'paint', operation:'finish', target, paintType:Number(type.value), colour:Number(input.value), pearlescent:paint.pearlescent || 0 })); indexed.appendChild(controlRow(`${target[0].toUpperCase()}${target.slice(1)} finish`, 'Native GTA paint type', type));
        const rgb = paint[`${target}Rgb`] || { r:0,g:0,b:0 }, wrap = document.createElement('div'); wrap.className = 'inline-control'; const picker = document.createElement('input'); picker.type = 'color'; picker.value = rgbHex(rgb); const hex = document.createElement('input'); hex.type = 'text'; hex.maxLength = 7; hex.value = picker.value.toUpperCase();
        const send = (colour) => { picker.value = rgbHex(colour); hex.value = picker.value.toUpperCase(); const key = `paint:${target}`; clearTimeout(timers.get(key)); timers.set(key, setTimeout(() => post('advancedAction', { group:'paint', operation:'custom', target, ...colour }), 120)); };
        picker.addEventListener('input', () => send(hexRgb(picker.value))); hex.addEventListener('change', () => { const value = hexRgb(hex.value); if (value) send(value); else toast('Use a six-digit hexadecimal colour.', 'warning'); }); wrap.append(picker, hex); custom.appendChild(controlRow(`${target[0].toUpperCase()}${target.slice(1)} custom RGB`, 'Colour picker and hexadecimal', wrap));
    });
    [['pearlescent','Pearlescent'],['wheel','Wheel colour'],['interior','Interior'],['dashboard','Dashboard']].forEach(([target,label]) => { const input=document.createElement('input'); input.type='number'; input.min=0; input.max=255; input.value=paint[target] ?? (target === 'wheel' ? paint.wheelColour : 0); input.addEventListener('change',()=>post('advancedAction',{group:'paint',operation:target==='pearlescent'||target==='wheel'?'extraColour':target,target,index:Number(input.value)})); indexed.appendChild(controlRow(label,'Indexed colour 0–255',input)); });
    renderLighting(); renderSwatches();
}

function renderSwatches() { const container=$('swatches'); container.replaceChildren(); (state.preferences?.colours||[]).forEach((rgb)=>{const button=document.createElement('button');button.type='button';button.className='swatch';button.style.background=rgbHex(rgb);button.title=rgbHex(rgb);button.addEventListener('click',()=>post('advancedAction',{group:'paint',operation:'custom',target:'primary',...rgb}));container.appendChild(button);}); }

function renderLighting() {
    const setup=state.setup?.lighting||{}, container=$('lightingControls'); container.replaceChildren();
    const neon=document.createElement('div'); ['Left','Right','Front','Rear'].forEach((label,index)=>{const input=document.createElement('input');input.type='checkbox';input.checked=setup.neon?.enabled?.[index]===true;input.addEventListener('change',()=>post('advancedAction',{group:'lighting',operation:'neonSide',side:index,enabled:input.checked}));const row=document.createElement('label');row.className='switch-row';row.textContent=`Neon ${label}`;row.appendChild(input);neon.appendChild(row);});container.appendChild(neon);
    const neonColour=document.createElement('input');neonColour.type='color';neonColour.value=rgbHex(setup.neon?.colour);neonColour.addEventListener('change',()=>post('advancedAction',{group:'lighting',operation:'neonColour',...hexRgb(neonColour.value)}));container.appendChild(controlRow('Neon colour','RGB',neonColour));
    const all=document.createElement('div');all.className='button-row';const on=document.createElement('button'),off=document.createElement('button');on.textContent='Enable All Neon';off.textContent='Disable All Neon';on.onclick=()=>post('advancedAction',{group:'lighting',operation:'neonAll',enabled:true});off.onclick=()=>post('advancedAction',{group:'lighting',operation:'neonAll',enabled:false});all.append(on,off);container.appendChild(all);
    const tint=document.createElement('input');tint.type='number';tint.min=-1;tint.max=6;tint.value=setup.windowTint??-1;tint.onchange=()=>post('advancedAction',{group:'lighting',operation:'tint',index:Number(tint.value)});container.appendChild(controlRow('Window tint','-1 stock, runtime validated',tint));
    const xenonColour=document.createElement('input');xenonColour.type='number';xenonColour.min=-1;xenonColour.max=14;xenonColour.value=setup.xenonColour??-1;xenonColour.onchange=()=>post('advancedAction',{group:'lighting',operation:'xenonColour',index:Number(xenonColour.value)});container.appendChild(controlRow('Xenon colour','-1 default, runtime palette',xenonColour));
    const smokeColour=document.createElement('input');smokeColour.type='color';smokeColour.value=rgbHex(setup.tyreSmokeColour);smokeColour.onchange=()=>post('advancedAction',{group:'lighting',operation:'smokeColour',...hexRgb(smokeColour.value)});container.appendChild(controlRow('Tyre smoke colour','RGB',smokeColour));
    const plateStyle=document.createElement('input');plateStyle.type='number';plateStyle.min=0;plateStyle.max=5;plateStyle.value=state.setup?.details?.plateStyle??0;plateStyle.onchange=()=>post('advancedAction',{group:'lighting',operation:'plateStyle',index:Number(plateStyle.value)});container.appendChild(controlRow('Plate style','Native index 0–5',plateStyle));
    const plate=document.createElement('input');plate.type='text';plate.maxLength=8;plate.value=state.setup?.details?.plateText||'';plate.onchange=()=>post('advancedAction',{group:'lighting',operation:'plateText',text:plate.value});container.appendChild(controlRow('Plate text','Maximum 8 characters',plate));
    const switches=document.createElement('div');[['Xenon','xenon','xenon'],['Tyre Smoke','tyreSmoke','smoke']].forEach(([label,key,operation])=>{const input=document.createElement('input');input.type='checkbox';input.checked=setup[key]===true;input.onchange=()=>post('advancedAction',{group:'lighting',operation,enabled:input.checked});const row=document.createElement('label');row.className='switch-row';row.textContent=label;row.appendChild(input);switches.appendChild(row);});container.appendChild(switches);
}

function renderLiveries() {
    const systems=state.liveries||{}, container=$('liverySystems'), names={native:'Native livery',mod:'Modification slot 48',roof:'Roof livery'};container.replaceChildren();let count=0;
    Object.entries(names).forEach(([key,label])=>{const system=systems[key];if(!system||!system.count)return;count++;const box=document.createElement('section');box.className='livery-system';const header=document.createElement('header');header.innerHTML=`<strong>${label}</strong><span>${system.current} / ${system.count-1}</span>`;const select=document.createElement('select');option(select,-1,'Select option');for(let i=0;i<system.count;i++)option(select,i,system.options?.find((x)=>x.index===i)?.label||`Option ${i+1}`);select.value=String(system.current);select.onchange=()=>post('advancedAction',{group:'livery',operation:'set',system:key,index:Number(select.value)});const step=document.createElement('div');step.className='button-row';const previous=document.createElement('button'),next=document.createElement('button');previous.textContent='Previous';next.textContent='Next';const move=(amount)=>{const value=(Number(select.value)+amount+system.count)%system.count;select.value=String(value);select.dispatchEvent(new Event('change'));};previous.onclick=()=>move(-1);next.onclick=()=>move(1);step.append(previous,next);const reset=document.createElement('button');reset.textContent='Reset to Spawn State';reset.onclick=()=>post('advancedAction',{group:'livery',operation:'reset',system:key});box.append(header,select,step,reset);container.appendChild(box);});
    $('liveriesEmpty').hidden=state.hasVehicle&&count>0;if(!state.hasVehicle)$('liveriesEmpty').textContent='No active vehicle.';else if(!count)$('liveriesEmpty').textContent='This vehicle exposes no livery system.';
}

function renderExtras() {
    const extras=state.extras||[],container=$('extrasList');container.replaceChildren();['enableExtras','disableExtras','resetExtras'].forEach((id)=>{$(id).disabled=!state.hasVehicle||!extras.length;});extras.forEach((extra)=>{const input=document.createElement('input');input.type='checkbox';input.checked=extra.enabled;input.onchange=()=>post('advancedAction',{group:'extras',operation:'set',id:extra.id,enabled:input.checked});const row=document.createElement('label');row.className='switch-row';row.textContent=`Extra ${extra.id}`;row.appendChild(input);container.appendChild(row);});$('extrasEmpty').hidden=state.hasVehicle&&extras.length>0;if(!state.hasVehicle)$('extrasEmpty').textContent='No active vehicle.';else if(!extras.length)$('extrasEmpty').textContent='This vehicle exposes no available extras.';
}

function renderPresets() {
    const list=$('presetList');list.replaceChildren();(state.presets||[]).forEach((preset)=>{const row=document.createElement('button');row.type='button';row.className=`list-row preset-row${selectedPreset===preset.id?' is-selected':''}`;const main=document.createElement('span');main.className='list-main';const title=document.createElement('span');title.className='list-title';title.textContent=`${preset.favorite?'[Favorite] ':''}${preset.name}`;const detail=document.createElement('span');detail.className='list-detail';detail.textContent=`${preset.vehicleModel||'Unknown model'} · updated ${preset.updatedAt||'unknown'}`;main.append(title,detail);row.appendChild(main);row.onclick=()=>{selectedPreset=preset.id;$('presetName').value=preset.name;renderPresets();};list.appendChild(row);});
}

function renderDiagnostics() { $('diagnosticsOutput').textContent=state.diagnostics?JSON.stringify(state.diagnostics,null,2):'No active vehicle.'; }

function updateState(next) {
    const incomingRevision = Number(next?.revision);
    const currentRevision = Number(state?.revision);
    if (Number.isFinite(incomingRevision) && Number.isFinite(currentRevision) && incomingRevision < currentRevision) return;
    const normalized = next && typeof next === 'object' ? { ...next } : {};
    normalized.activeVehicle = normalized.activeVehicle && typeof normalized.activeVehicle === 'object' ? normalized.activeVehicle : null;
    normalized.hasVehicle = Boolean(normalized.activeVehicle);
    normalized.capabilities = normalized.capabilities || null;
    normalized.setup = normalized.currentSetup || normalized.setup || null;
    normalized.preferences = normalized.preferences || {};
    normalized.history = normalized.history || {};
    normalized.presets = normalized.presets || [];
    const modelChanged=state.activeVehicle?.model!==normalized.activeVehicle?.model;state=normalized;
    if(modelChanged){timers.forEach((timer)=>clearTimeout(timer));timers.clear();disposeStanceControllers();stanceCameraFocused.clear();stanceRangeMode='safe';stanceExtendedConfirmed=false;selectedBodyType=null;bodyPreviewIndex=null;bodyConfirmed=new Map();}
    $('version').textContent=state.version?`v${state.version}`:'';
    const active=state.activeVehicle;
    $('vehicleStatus').textContent=active?`ACTIVE VEHICLE · ${active.displayName||active.model} · ${active.model} · ${(active.sourceType||'external').toUpperCase()} · ${active.ownership||'unknown'}`:'No active vehicle';
    document.querySelectorAll('.tab-panel:not([data-panel="vehicles"]) button, .tab-panel:not([data-panel="vehicles"]) input, .tab-panel:not([data-panel="vehicles"]) select, .tab-panel:not([data-panel="vehicles"]) textarea').forEach((control)=>{control.disabled=!state.hasVehicle;});
    $('undoButton').disabled=!(state.history?.undo>0);$('redoButton').disabled=!(state.history?.redo>0);
    const mode=state.preferences?.ui?.mode||'compact';app.classList.toggle('mode-expanded',mode==='expanded');app.classList.toggle('mode-compact',mode!=='expanded');$('modeButton').textContent=mode==='expanded'?'Compact':'Expand';
    populateFilterOptions();
    if(!filtersInitialized&&catalogue.length){const saved=state.preferences?.filters||{};if(saved.type&&[...$('typeFilter').options].some((o)=>o.value===saved.type))$('typeFilter').value=saved.type;if(saved.source&&[...$('sourceFilter').options].some((o)=>o.value===saved.source))$('sourceFilter').value=saved.source;if(Number.isInteger(saved.class)&&[...$('classFilter').options].some((o)=>o.value===String(saved.class)))$('classFilter').value=String(saved.class);filtersInitialized=true;}
    renderVehicles();renderBody();renderWheels();renderPerformance();renderPaint();renderLiveries();renderExtras();renderPresets();renderDiagnostics();
}

function confirmAction(message, action){if(window.confirm(message))action();}
async function replayHistory(direction){const result=await post('historyAction',{direction});if(result.success){bodyConfirmed=new Map();bodyPreviewIndex=null;renderBody();}}

$('closeButton').onclick=()=>post('close');$('spawnButton').onclick=spawnSelected;$('useCurrentVehicle').onclick=()=>post('useCurrentVehicle');$('refreshCatalogue').onclick=()=>post('manualRefresh');
['vehicleSearch','typeFilter','classFilter','sourceFilter'].forEach((id)=>$(id).addEventListener(id==='vehicleSearch'?'input':'change',()=>{renderVehicles();if(id!=='vehicleSearch')post('preferenceAction',{operation:'filters',value:{type:$('typeFilter').value,source:$('sourceFilter').value,class:$('classFilter').value==='all'?null:Number($('classFilter').value)}});}));
$('favoriteVehicle').onclick=()=>selectedModel?post('preferenceAction',{operation:'favoriteVehicle',model:selectedModel}):toast('Select a vehicle first.','warning');
$('undoButton').onclick=()=>replayHistory('undo');$('redoButton').onclick=()=>replayHistory('redo');
$('modeButton').onclick=()=>post('preferenceAction',{operation:'ui',mode:app.classList.contains('mode-expanded')?'compact':'expanded'});
$('bodyCategory').onchange=()=>{selectedBodyType=Number($('bodyCategory').value);bodyPreviewIndex=null;renderBody();};$('bodyPrevious').onclick=()=>previewBody(-1);$('bodyNext').onclick=()=>previewBody(1);$('bodyStock').onclick=()=>previewBody(0,-1);$('bodyConfirm').onclick=confirmBody;
$('bodyRevert').onclick=async()=>{const c=bodyCategory();if(!c)return;const result=await post('advancedAction',{group:'body',operation:'revert',modType:c.modType,index:bodyPreviewIndex});if(result.success)bodyPreviewIndex=bodyConfirmed.get(c.modType);};
$('bodyUnsafe').onclick=()=>{const c=bodyCategory();if(c)confirmAction('Skip this option for the current VehicleLab session?',()=>post('advancedAction',{group:'body',operation:'unsafe',modType:c.modType,index:bodyPreviewIndex}));};$('clearUnsafe').onclick=()=>post('advancedAction',{group:'body',operation:'clearUnsafe',modType:0,index:0});
$('resetWheels').onclick=()=>confirmAction('Restore wheels to the captured spawn state?',()=>post('advancedAction',{group:'wheels',operation:'reset'}));
$('resetStance').onclick=()=>confirmAction('Restore the exact captured stance baseline?',()=>{disposeStanceControllers();post('advancedAction',{group:'stance',operation:'reset',sequence:++stanceRequestSequence});});
const showStanceView=async(category)=>{const result=await post('focusTuningCamera',{category,reset:true});cameraActive=result.success;};
$('focusWheels').onclick=()=>showStanceView('wheels');$('viewStanceFront').onclick=()=>showStanceView('wheels');$('viewStanceRear').onclick=()=>showStanceView('rear_bumper');$('viewStanceSide').onclick=()=>showStanceView('general');
$('stockPerformance').onclick=()=>post('advancedAction',{group:'performance',operation:'stock'});$('maxPerformance').onclick=()=>post('advancedAction',{group:'performance',operation:'max'});$('toggleTurbo').onclick=()=>post('advancedAction',{group:'performance',operation:'turbo',enabled:!(state.setup?.toggleMods?.['18'])});$('resetPerformance').onclick=()=>confirmAction('Restore performance to the spawn state?',()=>post('advancedAction',{group:'performance',operation:'reset'}));
$('copyPrimary').onclick=()=>post('advancedAction',{group:'paint',operation:'copy',target:'primaryToSecondary'});$('copySecondary').onclick=()=>post('advancedAction',{group:'paint',operation:'copy',target:'secondaryToPrimary'});$('swapPaint').onclick=()=>post('advancedAction',{group:'paint',operation:'swap'});$('saveSwatch').onclick=()=>{const rgb=state.setup?.paint?.primaryRgb;if(rgb)post('preferenceAction',{operation:'saveColour',...rgb});};$('resetPaint').onclick=()=>confirmAction('Restore paint to the captured spawn state?',()=>post('advancedAction',{group:'paint',operation:'reset'}));
$('enableExtras').onclick=()=>post('advancedAction',{group:'extras',operation:'all',enabled:true});$('disableExtras').onclick=()=>post('advancedAction',{group:'extras',operation:'all',enabled:false});$('resetExtras').onclick=()=>confirmAction('Restore extras to their spawn states?',()=>post('advancedAction',{group:'extras',operation:'reset'}));
document.querySelectorAll('[data-utility]').forEach((button)=>button.onclick=()=>post('advancedAction',{group:'utility',operation:button.dataset.utility}));document.querySelectorAll('[data-door]').forEach((button)=>button.onclick=()=>{const door=Number(button.dataset.door);utilityState.doors[door]=!utilityState.doors[door];post('advancedAction',{group:'utility',operation:'door',door,open:utilityState.doors[door]});});$('dirtLevel').onchange=()=>post('advancedAction',{group:'utility',operation:'dirt',value:Number($('dirtLevel').value)});$('freezeVehicle').onclick=()=>{utilityState.frozen=!utilityState.frozen;post('advancedAction',{group:'utility',operation:'freeze',enabled:utilityState.frozen});};$('engineVehicle').onclick=()=>{utilityState.engine=!utilityState.engine;post('advancedAction',{group:'utility',operation:'engine',enabled:utilityState.engine});};$('lockVehicle').onclick=()=>{utilityState.locked=!utilityState.locked;post('advancedAction',{group:'utility',operation:'lock',enabled:utilityState.locked});};
$('respawnVehicle').onclick=()=>confirmAction('Delete and respawn the same model?',()=>post('respawnVehicle'));$('refreshVehicleCapabilities').onclick=()=>post('refreshVehicleCapabilities');$('releaseActiveVehicle').onclick=()=>confirmAction('Release this vehicle from VehicleLab without deleting it?',()=>post('releaseActiveVehicle'));$('deleteVehicle').onclick=()=>{const adopted=state.activeVehicle?.ownership==='adopted';confirmAction(adopted?'This vehicle was adopted from the world. Permanently delete the adopted vehicle entity?':'Delete the VehicleLab-spawned vehicle?',()=>post('deleteAdvancedVehicle'));};$('resetEntire').onclick=()=>confirmAction('Restore the complete captured activation baseline?',()=>post('advancedAction',{group:'utility',operation:'resetEntire'}));$('focusVehicle').onclick=async()=>{const result=await post('focusTuningCamera',{category:'general',reset:true});cameraActive=result.success;};
$('screenshotMode').onclick=async()=>{const result=await post('screenshotMode',{enabled:true,hideHud:true});if(result.success){screenshotActive=true;app.style.visibility='hidden';}};$('resetLighting').onclick=()=>confirmAction('Restore lighting to the spawn state?',()=>post('advancedAction',{group:'lighting',operation:'reset'}));
$('savePreset').onclick=()=>post('presetAction',{operation:'save',name:$('presetName').value});$('renamePreset').onclick=()=>selectedPreset&&post('presetAction',{operation:'rename',id:selectedPreset,name:$('presetName').value});$('duplicatePreset').onclick=()=>selectedPreset&&post('presetAction',{operation:'duplicate',id:selectedPreset});$('favoritePreset').onclick=()=>selectedPreset&&post('presetAction',{operation:'favorite',id:selectedPreset});$('deletePreset').onclick=()=>selectedPreset&&confirmAction('Delete this local preset?',()=>post('presetAction',{operation:'delete',id:selectedPreset}));
$('loadPreset').onclick=async()=>{if(!selectedPreset)return toast('Select a preset first.','warning');let result=await post('presetAction',{operation:'load',id:selectedPreset});if(!result.success&&result.error?.includes('another model')&&window.confirm(`${result.error}\nLoad compatible values anyway?`))result=await post('presetAction',{operation:'load',id:selectedPreset,confirmCrossModel:true});if(result.success){bodyConfirmed=new Map();bodyPreviewIndex=null;renderBody();}};
$('exportPreset').onclick=async()=>{if(!selectedPreset)return toast('Select a preset first.','warning');const result=await post('presetAction',{operation:'export',id:selectedPreset});if(result.success){await copyText(JSON.stringify(result.setup,null,2));toast('Preset JSON copied.','success');}};
$('importPreset').onclick=()=>{try{const setup=JSON.parse($('importJson').value);post('presetAction',{operation:'import',name:$('presetName').value,setup});}catch{toast('Preset JSON is invalid.','error');}};
$('copySetup').onclick=async()=>{const result=await post('getCurrentSetup');if(result.success){await copyText(JSON.stringify(result.setup,null,2));toast('Current setup JSON copied.','success');}};
$('refreshDiagnostics').onclick=async()=>{const result=await post('getDiagnostics');if(result.success){state.diagnostics=result.diagnostics;renderDiagnostics();}};$('copyDiagnostics').onclick=async()=>{const result=await post('getDiagnostics');if(result.success){await copyText(JSON.stringify(result.diagnostics,null,2));toast('Diagnostics JSON copied.','success');}};

function isTyping(target){return target instanceof HTMLInputElement||target instanceof HTMLTextAreaElement||target instanceof HTMLSelectElement||target?.isContentEditable;}
window.addEventListener('keydown',(event)=>{
    if(screenshotActive&&event.key==='Escape'){event.preventDefault();screenshotActive=false;app.style.visibility='';post('screenshotMode',{enabled:false,hideHud:false});return;}
    if(app.hidden||isTyping(event.target))return;
    if(event.key==='Escape'){event.preventDefault();post('close');return;}
    if(event.ctrlKey&&event.key.toLowerCase()==='z'){event.preventDefault();replayHistory('undo');return;}
    if(event.ctrlKey&&event.key.toLowerCase()==='y'){event.preventDefault();replayHistory('redo');return;}
    if(!event.ctrlKey&&event.key.toLowerCase()==='q'){event.preventDefault();switchTab(activeTab-1);return;}
    if(!event.ctrlKey&&event.key.toLowerCase()==='e'){event.preventDefault();switchTab(activeTab+1);return;}
    const tab=tabs[activeTab].dataset.tab;
    if(tab==='body'){
        const categories=state.body||[],index=Math.max(0,categories.findIndex((item)=>item.modType===selectedBodyType));
        if(event.key==='ArrowUp'){selectedBodyType=categories[(index-1+categories.length)%categories.length]?.modType;bodyPreviewIndex=null;renderBody();}
        else if(event.key==='ArrowDown'){selectedBodyType=categories[(index+1)%categories.length]?.modType;bodyPreviewIndex=null;renderBody();}
        else if(event.key==='ArrowLeft')previewBody(event.shiftKey?-5:-1);else if(event.key==='ArrowRight')previewBody(event.shiftKey?5:1);else if(event.key==='Enter')confirmBody();else if(event.key==='Backspace')previewBody(0,-1);else if(event.key.toLowerCase()==='r')$('bodyRevert').click();else return;
        event.preventDefault();return;
    }
    if(['a','d','w','s'].includes(event.key.toLowerCase())){event.preventDefault();const key=event.key.toLowerCase();post('cameraControl',{control:key==='a'||key==='d'?'rotate':'height',amount:key==='a'?-8:key==='d'?8:key==='w'?0.12:-0.12});}
    else if(event.key.toLowerCase()==='c'){event.preventDefault();cameraPreset=(cameraPreset+1)%cameraPresets.length;post('focusTuningCamera',{category:cameraPresets[cameraPreset],reset:false});cameraActive=true;}
    else if(event.key.toLowerCase()==='f'){event.preventDefault();post('focusTuningCamera',{category:tab==='wheels'?'wheels':tab,reset:false});cameraActive=true;}
    else if(event.key.toLowerCase()==='r'){event.preventDefault();post('focusTuningCamera',{category:'general',reset:true});cameraActive=true;}
});
window.addEventListener('wheel',(event)=>{if(app.hidden||isTyping(event.target)||!cameraActive)return;event.preventDefault();post('cameraControl',{control:'zoom',amount:event.deltaY>0?0.3:-0.3});},{passive:false});

window.addEventListener('message',(event)=>{const data=event.data||{};if(data.action==='open'){if(data.state)updateState(data.state);populateVehicles(data.vehicles);setVisible(true);}else if(data.action==='close'){cameraActive=false;setSpawnLoading(false);setVisible(false);}else if(data.action==='spawnLoading')setSpawnLoading(data.loading);else if(data.action==='spawnFailed'){setSpawnLoading(false);renderVehicles();}else if(data.action==='activeVehicleChanged'&&data.state){$('toastArea').replaceChildren();setSpawnLoading(false);updateState(data.state);}else if(data.action==='vehicleState'&&data.state)updateState(data.state);else if(data.action==='catalogue')populateVehicles(data.vehicles);else if(data.action==='toast')toast(data.message,data.type);});

post('ready').then((result)=>{if(result.state)updateState(result.state);if(result.vehicles)populateVehicles(result.vehicles);});
