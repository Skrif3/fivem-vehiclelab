const app = document.getElementById('app');
const vehicleSearch = document.getElementById('vehicleSearch');
const categoryFilter = document.getElementById('categoryFilter');
const sourceFilter = document.getElementById('sourceFilter');
const vehicleList = document.getElementById('vehicleList');
const vehicleCount = document.getElementById('vehicleCount');
const selectedVehicle = document.getElementById('selectedVehicle');
const refreshCatalogue = document.getElementById('refreshCatalogue');
const vehicleStatus = document.getElementById('vehicleStatus');
const messageBox = document.getElementById('message');
const primaryColour = document.getElementById('primaryColour');
const secondaryColour = document.getElementById('secondaryColour');
const primaryValue = document.getElementById('primaryValue');
const secondaryValue = document.getElementById('secondaryValue');
const liveryEmpty = document.getElementById('liveryEmpty');
const liveryControls = document.getElementById('liveryControls');
const liveryType = document.getElementById('liveryType');
const liveryIndex = document.getElementById('liveryIndex');
const tuningEmpty = document.getElementById('tuningEmpty');
const tuningList = document.getElementById('tuningList');
const tuningNavigator = document.getElementById('tuningNavigator');
const tuningCategoryName = document.getElementById('tuningCategoryName');
const tuningOptionReadout = document.getElementById('tuningOptionReadout');
const tuningConfirmedReadout = document.getElementById('tuningConfirmedReadout');
const extrasEmpty = document.getElementById('extrasEmpty');
const extrasList = document.getElementById('extrasList');
const spawnButton = document.getElementById('spawnButton');
const previousLivery = document.getElementById('previousLivery');
const nextLivery = document.getElementById('nextLivery');
const maxPerformance = document.getElementById('maxPerformance');
const resetModifications = document.getElementById('resetModifications');
const previousPart = document.getElementById('previousPart');
const nextPart = document.getElementById('nextPart');
const confirmPart = document.getElementById('confirmPart');
const revertPreview = document.getElementById('revertPreview');
const tabs = [...document.querySelectorAll('.tab')];

let currentState = { hasVehicle: false, liveries: { available: false }, tuning: [], extras: [] };
let catalogue = [];
let selectedModel = null;
let selectedTuningId = null;
let selectedExtraId = null;
let pendingExtraState = null;
let activeTabIndex = 0;
let messageTimer = null;
let tuningBusy = false;
let extrasBusy = false;
let cameraBusy = false;
let cameraActive = false;
let lastTuningRequest = 0;
let lastCameraRequest = 0;
let pendingCameraFocus = null;
let cameraIntentToken = 0;
const confirmationTimers = new WeakMap();

app.hidden = true;
app.classList.add('is-hidden');
app.setAttribute('aria-hidden', 'true');

async function post(name, data = {}, quiet = false) {
    try {
        const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        });
        const result = await response.json();
        if (result.state) updateState(result.state);
        if (!quiet && result.success && result.message) showMessage(result.message, 'success');
        if (!quiet && !result.success && (result.error || result.message)) {
            showMessage(result.error || result.message, 'error');
        }
        return result;
    } catch (error) {
        if (!quiet) showMessage(`NUI request failed: ${error.message}`, 'error');
        return { success: false, error: error.message };
    }
}

async function runBusy(control, request) {
    if (!control || control.dataset.busy === 'true' || control.disabled) return undefined;
    const wasDisabled = control.disabled;
    control.dataset.busy = 'true';
    control.disabled = true;
    try {
        return await request();
    } finally {
        delete control.dataset.busy;
        if (control.isConnected) control.disabled = wasDisabled;
    }
}

function showMessage(text, type = '') {
    window.clearTimeout(messageTimer);
    messageBox.textContent = text || '';
    messageBox.className = text ? `message has-message ${type}` : 'message';
    if (text && type !== 'error') messageTimer = window.setTimeout(() => showMessage(''), 2600);
}

function confirmButtonAction(button, action) {
    if (button.dataset.confirming === 'true') {
        window.clearTimeout(confirmationTimers.get(button));
        button.textContent = button.dataset.originalText;
        delete button.dataset.confirming;
        delete button.dataset.originalText;
        action();
        return;
    }
    button.dataset.confirming = 'true';
    button.dataset.originalText = button.textContent;
    button.textContent = 'Click again to confirm';
    showMessage('Press the same button again to confirm.');
    confirmationTimers.set(button, window.setTimeout(() => {
        if (!button.isConnected) return;
        button.textContent = button.dataset.originalText || button.textContent;
        delete button.dataset.confirming;
        delete button.dataset.originalText;
    }, 3500));
}

function setVisible(visible) {
    app.hidden = !visible;
    app.classList.toggle('is-hidden', !visible);
    app.setAttribute('aria-hidden', String(!visible));
    if (!visible) {
        cameraActive = false;
        pendingCameraFocus = null;
        cameraIntentToken += 1;
    }
}

function clearUiState() {
    showMessage('');
    selectedTuningId = null;
    selectedExtraId = null;
    pendingExtraState = null;
    updateState({ hasVehicle: false, model: null, liveries: { available: false }, tuning: [], extras: [] });
}

function setFilterOptions(select, options, previous) {
    const fragment = document.createDocumentFragment();
    options.forEach(({ value, label }) => {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = label;
        fragment.appendChild(option);
    });
    select.replaceChildren(fragment);
    select.value = options.some((option) => option.value === previous) ? previous : 'all';
}

function configureVehicleFilters() {
    const previousCategory = categoryFilter.value || 'all';
    const previousSource = sourceFilter.value || 'all';
    const categories = [...new Set(catalogue.map((vehicle) => vehicle.category)
        .filter((category) => category && category !== 'Add-on' && category !== 'Base Game'))]
        .sort((left, right) => left.localeCompare(right));
    const resources = [...new Set(catalogue.filter((vehicle) => vehicle.sourceType !== 'base')
        .map((vehicle) => vehicle.resource).filter(Boolean))]
        .sort((left, right) => left.localeCompare(right));

    setFilterOptions(categoryFilter, [
        { value: 'all', label: 'All' },
        { value: 'addon', label: 'Add-on' },
        { value: 'base', label: 'Base Game' },
        ...categories.map((category) => ({ value: `category:${category}`, label: category }))
    ], previousCategory);
    setFilterOptions(sourceFilter, [
        { value: 'all', label: 'All resources' },
        { value: 'base', label: 'Base Game' },
        ...resources.map((resource) => ({ value: `resource:${resource}`, label: resource }))
    ], previousSource);
}

function matchesVehicleFilters(vehicle) {
    const query = vehicleSearch.value.trim().toLocaleLowerCase();
    if (query) {
        const searchable = [vehicle.model, vehicle.label, vehicle.manufacturer, vehicle.resource]
            .filter(Boolean).join(' ').toLocaleLowerCase();
        if (!searchable.includes(query)) return false;
    }
    const category = categoryFilter.value;
    if (category === 'addon' && vehicle.sourceType === 'base') return false;
    if (category === 'base' && vehicle.sourceType !== 'base') return false;
    if (category.startsWith('category:') && vehicle.category !== category.slice(9)) return false;
    const source = sourceFilter.value;
    if (source === 'base' && vehicle.sourceType !== 'base') return false;
    if (source.startsWith('resource:') && vehicle.resource !== source.slice(9)) return false;
    return true;
}

function renderVehicleList() {
    const filtered = catalogue.filter(matchesVehicleFilters);
    const fragment = document.createDocumentFragment();
    filtered.forEach((vehicle) => {
        const item = document.createElement('button');
        item.type = 'button';
        item.className = `vehicle-item${vehicle.model === selectedModel ? ' is-selected' : ''}`;
        item.dataset.model = vehicle.model;
        item.setAttribute('role', 'option');
        item.setAttribute('aria-selected', String(vehicle.model === selectedModel));
        const main = document.createElement('span');
        main.className = 'vehicle-main';
        const name = document.createElement('span');
        name.className = 'vehicle-name';
        name.textContent = vehicle.label || vehicle.model;
        const details = document.createElement('span');
        details.className = 'vehicle-details';
        details.textContent = [vehicle.manufacturer, vehicle.model, vehicle.sourceType === 'base' ? null : vehicle.resource]
            .filter(Boolean).join(' · ');
        main.append(name, details);
        const side = document.createElement('span');
        side.className = 'vehicle-side';
        const badge = document.createElement('span');
        badge.className = `source-badge${vehicle.sourceType === 'base' ? '' : ' addon'}`;
        badge.textContent = vehicle.sourceType === 'base' ? 'GTA' : 'ADD-ON';
        const categoryName = document.createElement('span');
        categoryName.className = 'vehicle-category';
        categoryName.textContent = vehicle.category || 'Uncategorized';
        side.append(badge, categoryName);
        item.append(main, side);
        item.addEventListener('click', () => {
            selectedModel = vehicle.model;
            renderVehicleList();
        });
        item.addEventListener('dblclick', () => spawnSelectedVehicle());
        fragment.appendChild(item);
    });
    vehicleList.replaceChildren(fragment);
    if (filtered.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'vehicle-list-empty';
        empty.textContent = catalogue.length === 0 ? 'Waiting for the validated vehicle catalogue...' : 'No vehicles match these filters.';
        vehicleList.appendChild(empty);
    }
    vehicleCount.textContent = filtered.length === catalogue.length
        ? `${filtered.length} ${filtered.length === 1 ? 'vehicle' : 'vehicles'}`
        : `${filtered.length} / ${catalogue.length} vehicles`;
    const selected = catalogue.find((vehicle) => vehicle.model === selectedModel);
    selectedVehicle.textContent = selected ? selected.model : 'Nothing selected';
    spawnButton.disabled = !selected;
}

function populateVehicles(vehicles) {
    const previous = selectedModel;
    catalogue = (Array.isArray(vehicles) ? vehicles : []).filter((vehicle) => (
        vehicle && typeof vehicle.model === 'string' && /^[a-z0-9_-]{1,64}$/i.test(vehicle.model)
    ));
    selectedModel = catalogue.some((vehicle) => vehicle.model === previous) ? previous : (catalogue[0]?.model || null);
    configureVehicleFilters();
    renderVehicleList();
}

function channelToHex(channel) {
    return Math.max(0, Math.min(255, Number(channel) || 0)).toString(16).padStart(2, '0');
}

function rgbToHex(colour) {
    return `#${channelToHex(colour?.r)}${channelToHex(colour?.g)}${channelToHex(colour?.b)}`;
}

function hexToRgb(hex) {
    const match = /^#([0-9a-f]{6})$/i.exec(hex);
    if (!match) return null;
    return {
        r: Number.parseInt(match[1].slice(0, 2), 16),
        g: Number.parseInt(match[1].slice(2, 4), 16),
        b: Number.parseInt(match[1].slice(4, 6), 16)
    };
}

function updatePaint(state) {
    const disabled = !state.hasVehicle;
    primaryColour.disabled = disabled;
    secondaryColour.disabled = disabled;
    primaryColour.value = state.paint ? rgbToHex(state.paint.primary) : '#000000';
    secondaryColour.value = state.paint ? rgbToHex(state.paint.secondary) : '#000000';
    primaryValue.textContent = primaryColour.value.toUpperCase();
    secondaryValue.textContent = secondaryColour.value.toUpperCase();
}

function updateLiveries(state) {
    const livery = state.liveries || { available: false };
    liveryEmpty.classList.toggle('is-hidden', Boolean(state.hasVehicle && livery.available));
    liveryControls.classList.toggle('is-hidden', !state.hasVehicle || !livery.available);
    if (!state.hasVehicle) liveryEmpty.textContent = 'Spawn a vehicle to inspect its liveries.';
    else if (!livery.available) liveryEmpty.textContent = 'No native or mod-slot liveries are available for this vehicle.';
    else {
        liveryType.textContent = livery.implementation;
        liveryIndex.textContent = `Index ${livery.index} / ${livery.count - 1}`;
    }
}

function tuningCategories() {
    return Array.isArray(currentState.tuning) ? currentState.tuning : [];
}

function selectedTuningCategory() {
    const categories = tuningCategories();
    return categories.find((category) => category.id === selectedTuningId) || categories[0] || null;
}

function optionDetails(category) {
    const options = Array.isArray(category?.options) ? category.options : [];
    const position = Math.max(0, options.findIndex((option) => option.index === category.value));
    const option = options[position];
    return { options, position, option, text: option ? `${option.label} — ${position + 1} / ${options.length}` : 'Unavailable' };
}

function selectTuningCategory(index, focusCamera = true) {
    const categories = tuningCategories();
    if (!categories.length) return;
    const wrapped = (index + categories.length) % categories.length;
    selectedTuningId = categories[wrapped].id;
    renderTuning();
    document.querySelector(`.tuning-item[data-category="${CSS.escape(selectedTuningId)}"]`)
        ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    if (focusCamera && currentState.cameraEnabled) focusCameraFor(selectedTuningId);
}

function buildTuningRow(category) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = `tuning-item${category.id === selectedTuningId ? ' is-selected' : ''}`;
    row.dataset.category = category.id;
    const name = document.createElement('span');
    name.className = 'part-name';
    name.textContent = category.label;
    const value = document.createElement('span');
    const details = optionDetails(category);
    value.className = `part-value ${category.value === category.confirmed ? 'is-confirmed' : 'is-preview'}`;
    value.textContent = details.text;
    value.title = category.value === category.confirmed ? 'Confirmed option' : 'Live preview';
    row.append(name, value);
    row.addEventListener('click', () => {
        selectedTuningId = category.id;
        renderTuning();
        if (currentState.cameraEnabled) focusCameraFor(category.id);
    });
    return row;
}

function renderTuning() {
    const categories = tuningCategories();
    if (!categories.some((category) => category.id === selectedTuningId)) selectedTuningId = categories[0]?.id || null;
    tuningList.replaceChildren(...categories.map(buildTuningRow));
    tuningEmpty.classList.toggle('is-hidden', categories.length > 0);
    tuningNavigator.classList.toggle('is-hidden', categories.length === 0);
    if (!currentState.hasVehicle) tuningEmpty.textContent = 'Spawn a vehicle to inspect available modifications.';
    else if (!categories.length) tuningEmpty.textContent = 'No supported modifications are available for this vehicle.';
    const category = selectedTuningCategory();
    tuningCategoryName.textContent = category?.label || '—';
    tuningOptionReadout.textContent = category ? optionDetails(category).text : '—';
    const confirmedOption = category?.options?.find((option) => option.index === category.confirmed);
    tuningConfirmedReadout.textContent = `Confirmed: ${confirmedOption?.label || '—'}`;
    const disabled = !category || tuningBusy;
    [previousPart, nextPart, confirmPart, revertPreview].forEach((button) => { button.disabled = disabled; });
    utilityPreviousPart.disabled = disabled;
    utilityNextPart.disabled = disabled;
    maxPerformance.disabled = !currentState.hasVehicle;
    resetModifications.disabled = !currentState.hasVehicle;
}

async function previewTuning(step) {
    const now = performance.now();
    if (tuningBusy || now - lastTuningRequest < 120) return;
    const category = selectedTuningCategory();
    if (!category) return;
    const { options, position } = optionDetails(category);
    if (!options.length) return;
    const nextPosition = Math.max(0, Math.min(options.length - 1, position + step));
    if (nextPosition === position) return;
    lastTuningRequest = now;
    tuningBusy = true;
    renderTuning();
    try {
        await post('previewModification', { category: category.id, index: options[nextPosition].index });
    } finally {
        tuningBusy = false;
        renderTuning();
    }
}

async function confirmTuning() {
    if (tuningBusy) return;
    const category = selectedTuningCategory();
    if (!category) return;
    tuningBusy = true;
    renderTuning();
    try {
        await post('confirmModification', { category: category.id, index: category.value });
    } finally {
        tuningBusy = false;
        renderTuning();
    }
}

async function setTuningStock() {
    if (tuningBusy) return;
    const category = selectedTuningCategory();
    if (!category || !category.options.some((option) => option.index === -1)) {
        showMessage('Stock is unavailable for this category.', 'error');
        return;
    }
    tuningBusy = true;
    try {
        const result = await post('previewModification', { category: category.id, index: -1 });
        if (result.success) await post('confirmModification', { category: category.id, index: -1 });
    } finally {
        tuningBusy = false;
        renderTuning();
    }
}

async function revertTuning() {
    if (tuningBusy) return;
    const category = selectedTuningCategory();
    if (!category) return;
    tuningBusy = true;
    try {
        await post('revertModification', { category: category.id });
    } finally {
        tuningBusy = false;
        renderTuning();
    }
}

function extras() {
    return Array.isArray(currentState.extras) ? currentState.extras : [];
}

function selectedExtra() {
    return extras().find((extra) => extra.id === selectedExtraId) || extras()[0] || null;
}

function selectExtra(index) {
    const available = extras();
    if (!available.length) return;
    selectedExtraId = available[(index + available.length) % available.length].id;
    pendingExtraState = null;
    renderExtras();
    document.querySelector(`.extra-item[data-extra="${selectedExtraId}"]`)
        ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

function renderExtras() {
    const available = extras();
    if (!available.some((extra) => extra.id === selectedExtraId)) selectedExtraId = available[0]?.id ?? null;
    const fragment = document.createDocumentFragment();
    available.forEach((extra) => {
        const row = document.createElement('div');
        row.className = `extra-item${extra.id === selectedExtraId ? ' is-selected' : ''}`;
        row.dataset.extra = String(extra.id);
        const name = document.createElement('span');
        name.textContent = `Extra ${extra.id}`;
        const control = document.createElement('button');
        control.type = 'button';
        const pending = extra.id === selectedExtraId && pendingExtraState !== null ? pendingExtraState : extra.enabled;
        control.className = `extra-state${pending !== extra.enabled ? ' is-preview' : ''}`;
        control.textContent = pending ? 'Enabled' : 'Disabled';
        control.addEventListener('click', () => {
            selectedExtraId = extra.id;
            pendingExtraState = !extra.enabled;
            applySelectedExtra();
        });
        row.addEventListener('click', (event) => {
            if (event.target === control) return;
            selectedExtraId = extra.id;
            pendingExtraState = null;
            renderExtras();
        });
        row.append(name, control);
        fragment.appendChild(row);
    });
    extrasList.replaceChildren(fragment);
    extrasEmpty.classList.toggle('is-hidden', available.length > 0);
    if (!currentState.hasVehicle) extrasEmpty.textContent = 'Spawn a vehicle to inspect available extras.';
    else if (!available.length) extrasEmpty.textContent = 'This vehicle exposes no extras.';
}

async function applySelectedExtra() {
    if (extrasBusy) return;
    const extra = selectedExtra();
    if (!extra) return;
    const enabled = pendingExtraState === null ? extra.enabled : pendingExtraState;
    extrasBusy = true;
    try {
        const result = await post('setExtra', { id: extra.id, enabled });
        if (result.success) pendingExtraState = null;
    } finally {
        extrasBusy = false;
        renderExtras();
    }
}

function updateState(state) {
    const previousModel = currentState.model;
    currentState = state || { hasVehicle: false, liveries: { available: false }, tuning: [], extras: [] };
    const modelChanged = previousModel !== currentState.model;
    if (modelChanged) {
        selectedTuningId = null;
        selectedExtraId = null;
        pendingExtraState = null;
        cameraActive = false;
    }
    vehicleStatus.textContent = currentState.hasVehicle ? `Active: ${currentState.model}` : 'No test vehicle';
    if (currentState.model && catalogue.some((vehicle) => vehicle.model === currentState.model)) {
        selectedModel = currentState.model;
        renderVehicleList();
    }
    updatePaint(currentState);
    updateLiveries(currentState);
    renderTuning();
    renderExtras();
}

async function focusCameraFor(category, reset = false) {
    if (!currentState.hasVehicle || !currentState.cameraEnabled) return;
    if (cameraBusy) {
        pendingCameraFocus = { category, reset };
        return;
    }
    pendingCameraFocus = null;
    cameraBusy = true;
    const intentToken = ++cameraIntentToken;
    try {
        const result = await post('focusTuningCamera', { category, reset }, true);
        if (intentToken === cameraIntentToken && !app.hidden) cameraActive = result.success;
    } finally {
        window.setTimeout(() => {
            cameraBusy = false;
            if (pendingCameraFocus) {
                const pending = pendingCameraFocus;
                pendingCameraFocus = null;
                focusCameraFor(pending.category, pending.reset);
            }
        }, 400);
    }
}

function switchTab(index) {
    activeTabIndex = (index + tabs.length) % tabs.length;
    tabs.forEach((tab, tabIndex) => tab.classList.toggle('is-active', tabIndex === activeTabIndex));
    document.querySelectorAll('.tab-panel').forEach((panel) => {
        panel.classList.toggle('is-active', panel.dataset.panel === tabs[activeTabIndex].dataset.tab);
    });
    const tabName = tabs[activeTabIndex].dataset.tab;
    if (tabName === 'tuning' && selectedTuningCategory() && currentState.cameraEnabled) {
        focusCameraFor(selectedTuningId);
    } else if (tabName !== 'utilities' && (cameraActive || cameraBusy)) {
        cameraActive = false;
        pendingCameraFocus = null;
        cameraIntentToken += 1;
        post('closeTuningCamera', {}, true);
    }
}

tabs.forEach((tab, index) => tab.addEventListener('click', () => switchTab(index)));

function spawnSelectedVehicle() {
    if (!selectedModel) {
        showMessage('No vehicle is selected.', 'error');
        return undefined;
    }
    return runBusy(spawnButton, () => post('spawnVehicle', { model: selectedModel }));
}

document.getElementById('closeButton').addEventListener('click', () => post('close'));
spawnButton.addEventListener('click', spawnSelectedVehicle);
vehicleSearch.addEventListener('input', renderVehicleList);
categoryFilter.addEventListener('change', renderVehicleList);
sourceFilter.addEventListener('change', renderVehicleList);
refreshCatalogue.addEventListener('click', () => runBusy(refreshCatalogue, () => post('refreshCatalogue')));

const deleteButton = document.getElementById('deleteButton');
const repairButton = document.getElementById('repairButton');
const cleanButton = document.getElementById('cleanButton');
const resetButton = document.getElementById('resetButton');
const focusVehicle = document.getElementById('focusVehicle');
const randomVisualBuild = document.getElementById('randomVisualBuild');
const saveSetup = document.getElementById('saveSetup');
const loadSetup = document.getElementById('loadSetup');
const copySetup = document.getElementById('copySetup');
const resetVisuals = document.getElementById('resetVisuals');
const utilityPreviousPart = document.getElementById('utilityPreviousPart');
const utilityNextPart = document.getElementById('utilityNextPart');

deleteButton.addEventListener('click', () => runBusy(deleteButton, () => post('deleteVehicle')));
repairButton.addEventListener('click', () => runBusy(repairButton, () => post('repairVehicle')));
cleanButton.addEventListener('click', () => runBusy(cleanButton, () => post('cleanVehicle')));
resetButton.addEventListener('click', () => runBusy(resetButton, () => post('resetVehicle')));
previousLivery.addEventListener('click', () => runBusy(previousLivery, () => post('changeLivery', { direction: -1 })));
nextLivery.addEventListener('click', () => runBusy(nextLivery, () => post('changeLivery', { direction: 1 })));
maxPerformance.addEventListener('click', () => runBusy(maxPerformance, () => post('maxPerformance')));
resetModifications.addEventListener('click', () => {
    confirmButtonAction(resetModifications, () => {
        runBusy(resetModifications, () => post('resetModifications'));
    });
});
previousPart.addEventListener('click', () => previewTuning(-1));
nextPart.addEventListener('click', () => previewTuning(1));
confirmPart.addEventListener('click', confirmTuning);
revertPreview.addEventListener('click', revertTuning);
focusVehicle.addEventListener('click', () => focusCameraFor('general', true));
randomVisualBuild.addEventListener('click', () => runBusy(randomVisualBuild, () => post('randomVisualBuild')));
utilityPreviousPart.addEventListener('click', () => previewTuning(-1));
utilityNextPart.addEventListener('click', () => previewTuning(1));
saveSetup.addEventListener('click', () => runBusy(saveSetup, () => post('saveSetup')));
loadSetup.addEventListener('click', () => runBusy(loadSetup, () => post('loadSetup')));
resetVisuals.addEventListener('click', () => {
    confirmButtonAction(resetVisuals, () => {
        runBusy(resetVisuals, () => post('resetVisuals'));
    });
});

async function copyText(text) {
    if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        return;
    }
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand('copy');
    textarea.remove();
    if (!copied) throw new Error('Clipboard access was denied.');
}

copySetup.addEventListener('click', () => runBusy(copySetup, async () => {
    const result = await post('getSetupJson');
    if (!result.success || !result.setup) return result;
    try {
        await copyText(JSON.stringify(result.setup, null, 2));
        showMessage('Setup JSON copied.', 'success');
    } catch (error) {
        showMessage(`Could not copy setup JSON: ${error.message}`, 'error');
    }
    return result;
}));

function bindColour(input, valueLabel, target) {
    input.addEventListener('input', () => {
        valueLabel.textContent = input.value.toUpperCase();
        const rgb = hexToRgb(input.value);
        if (rgb) post('setColour', { target, ...rgb });
    });
}
bindColour(primaryColour, primaryValue, 'primary');
bindColour(secondaryColour, secondaryValue, 'secondary');

function isTypingTarget(target) {
    if (!(target instanceof HTMLElement)) return false;
    if (target.isContentEditable || target instanceof HTMLTextAreaElement) return true;
    if (!(target instanceof HTMLInputElement)) return false;
    return ['search', 'text', 'number', 'color'].includes(target.type);
}

function currentTabName() {
    return tabs[activeTabIndex]?.dataset.tab;
}

function handleTuningKey(event) {
    const categories = tuningCategories();
    const index = Math.max(0, categories.findIndex((category) => category.id === selectedTuningId));
    if (event.key === 'ArrowUp') selectTuningCategory(index - 1);
    else if (event.key === 'ArrowDown') selectTuningCategory(index + 1);
    else if (event.key === 'ArrowLeft') previewTuning(event.shiftKey ? -5 : -1);
    else if (event.key === 'ArrowRight') previewTuning(event.shiftKey ? 5 : 1);
    else if (event.key === 'Enter') confirmTuning();
    else if (event.key === 'Backspace') setTuningStock();
    else return false;
    return true;
}

function handleExtrasKey(event) {
    const available = extras();
    const index = Math.max(0, available.findIndex((extra) => extra.id === selectedExtraId));
    if (event.key === 'ArrowUp') selectExtra(index - 1);
    else if (event.key === 'ArrowDown') selectExtra(index + 1);
    else if (event.key === 'ArrowLeft') { pendingExtraState = false; renderExtras(); }
    else if (event.key === 'ArrowRight') { pendingExtraState = true; renderExtras(); }
    else if (event.key === 'Enter') applySelectedExtra();
    else return false;
    return true;
}

function controlCamera(control, amount) {
    const now = performance.now();
    if (!cameraActive || cameraBusy || now - lastCameraRequest < 120) return;
    lastCameraRequest = now;
    cameraBusy = true;
    post('cameraControl', { control, amount }, true).then((result) => {
        if (!result.success && result.error !== 'The tuning camera is busy.') cameraActive = false;
    }).finally(() => window.setTimeout(() => { cameraBusy = false; }, 380));
}

window.addEventListener('keydown', (event) => {
    if (app.hidden || isTypingTarget(event.target)) return;
    if (event.key === 'Escape') {
        event.preventDefault();
        post('close');
        return;
    }
    if (!event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === 'q') {
        event.preventDefault();
        switchTab(activeTabIndex - 1);
        return;
    }
    if (!event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === 'e') {
        event.preventDefault();
        switchTab(activeTabIndex + 1);
        return;
    }
    if (cameraActive && ['a', 'd', 'w', 's'].includes(event.key.toLowerCase())) {
        event.preventDefault();
        const key = event.key.toLowerCase();
        if (key === 'a') controlCamera('rotate', -8);
        else if (key === 'd') controlCamera('rotate', 8);
        else if (key === 'w') controlCamera('height', 0.12);
        else controlCamera('height', -0.12);
        return;
    }
    let handled = false;
    if (currentTabName() === 'tuning') handled = handleTuningKey(event);
    else if (currentTabName() === 'extras') handled = handleExtrasKey(event);
    if (handled || ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' ', 'Backspace'].includes(event.key)) {
        event.preventDefault();
    }
});

window.addEventListener('wheel', (event) => {
    if (app.hidden || !cameraActive || isTypingTarget(event.target)) return;
    event.preventDefault();
    controlCamera('zoom', event.deltaY > 0 ? 0.3 : -0.3);
}, { passive: false });

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        populateVehicles(data.vehicles);
        if (data.state) updateState(data.state);
        setVisible(true);
    } else if (data.action === 'close') {
        setVisible(false);
        if (data.clear === true) clearUiState();
    } else if (data.action === 'vehicleState' && data.state) updateState(data.state);
    else if (data.action === 'catalogue') populateVehicles(data.vehicles);
});

post('ready').then((result) => {
    populateVehicles(result.vehicles);
    if (result.state) updateState(result.state);
});
