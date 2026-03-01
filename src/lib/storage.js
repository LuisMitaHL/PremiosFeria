/* ============================================
   Storage Layer — localStorage CRUD helpers
   ============================================ */

const KEYS = {
    GROUPS: 'fp_groups',
    PARTICIPANT: 'fp_participant',
    SCAN_LOG: 'fp_scan_log',
    PARTICIPANTS_DB: 'fp_participants_db',
    REWARDS: 'fp_rewards',
    ADMIN_SECRET: 'fp_admin_secret',
};

// --- Helpers ---
function get(key, fallback = null) {
    try {
        const raw = localStorage.getItem(key);
        return raw ? JSON.parse(raw) : fallback;
    } catch {
        return fallback;
    }
}

function set(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
}

export function generateId() {
    return crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2);
}

// --- Groups ---
export function getGroups() {
    return get(KEYS.GROUPS, []);
}

export function saveGroups(groups) {
    set(KEYS.GROUPS, groups);
}

export function addGroup(group) {
    const groups = getGroups();
    const newGroup = {
        id: generateId(),
        createdAt: Date.now(),
        ...group,
    };
    groups.push(newGroup);
    saveGroups(groups);
    return newGroup;
}

export function updateGroup(id, updates) {
    const groups = getGroups();
    const idx = groups.findIndex(g => g.id === id);
    if (idx !== -1) {
        groups[idx] = { ...groups[idx], ...updates };
        saveGroups(groups);
        return groups[idx];
    }
    return null;
}

export function deleteGroup(id) {
    const groups = getGroups().filter(g => g.id !== id);
    saveGroups(groups);
}

// --- Participant (current device) ---
export function getParticipant() {
    return get(KEYS.PARTICIPANT, null);
}

export function saveParticipant(participant) {
    set(KEYS.PARTICIPANT, participant);
    // Also update in DB
    const db = getParticipantsDB();
    const idx = db.findIndex(p => p.id === participant.id);
    if (idx !== -1) {
        db[idx] = participant;
    } else {
        db.push(participant);
    }
    set(KEYS.PARTICIPANTS_DB, db);
}

export function registerParticipant({ name, email, universityId }) {
    const participant = {
        id: generateId(),
        name,
        email,
        universityId,
        points: 0,
        visitedStands: [],
        activitiesCompleted: [],
        claimedRewards: [],
        registeredAt: Date.now(),
        fingerprint: getDeviceFingerprint(),
    };
    saveParticipant(participant);
    return participant;
}

// --- Participants DB (all participants) ---
export function getParticipantsDB() {
    return get(KEYS.PARTICIPANTS_DB, []);
}

export function addPoints(participantId, standId, points, type = 'visit', groupName = '') {
    const participant = getParticipant();
    if (!participant || participant.id !== participantId) return null;

    participant.points += points;

    if (type === 'visit' && !participant.visitedStands.includes(standId)) {
        participant.visitedStands.push(standId);
    }
    if (type === 'activity' && !participant.activitiesCompleted.includes(standId)) {
        participant.activitiesCompleted.push(standId);
    }

    saveParticipant(participant);

    // Log the scan
    logScan(participantId, standId, points, type, groupName);

    return participant;
}

// --- Scan Log ---
export function getScanLog() {
    return get(KEYS.SCAN_LOG, []);
}

function logScan(participantId, standId, points, type, groupName) {
    const log = getScanLog();
    log.unshift({
        id: generateId(),
        participantId,
        standId,
        points,
        type,
        groupName,
        timestamp: Date.now(),
    });
    set(KEYS.SCAN_LOG, log);
}

export function getLastScanForStand(participantId, standId) {
    const log = getScanLog();
    return log.find(s => s.participantId === participantId && s.standId === standId);
}

// --- Leaderboard ---
export function getLeaderboard() {
    const db = getParticipantsDB();
    return db.sort((a, b) => b.points - a.points);
}

// --- Rewards ---
export function getDefaultRewards() {
    return [
        { id: 'r1', name: 'Sticker Pack', description: 'Pack de stickers exclusivos de la feria', cost: 50, emoji: '🎨' },
        { id: 'r2', name: 'Camiseta Oficial', description: 'Camiseta oficial del evento', cost: 200, emoji: '👕' },
        { id: 'r3', name: 'Taza Personalizada', description: 'Taza con diseño de la feria', cost: 100, emoji: '☕' },
        { id: 'r4', name: 'Libreta Premium', description: 'Libreta de notas con el branding del evento', cost: 75, emoji: '📓' },
        { id: 'r5', name: 'Power Bank', description: 'Cargador portátil con logo de la feria', cost: 300, emoji: '🔋' },
        { id: 'r6', name: 'Certificado VIP', description: 'Certificado de participación VIP firmado', cost: 150, emoji: '🏆' },
    ];
}

export function getRewards() {
    return get(KEYS.REWARDS, getDefaultRewards());
}

export function claimReward(rewardId) {
    const participant = getParticipant();
    if (!participant) return { success: false, reason: 'No registrado' };

    const rewards = getRewards();
    const reward = rewards.find(r => r.id === rewardId);
    if (!reward) return { success: false, reason: 'Premio no encontrado' };

    if (participant.claimedRewards.includes(rewardId)) {
        return { success: false, reason: 'Ya reclamaste este premio' };
    }

    if (participant.points < reward.cost) {
        return { success: false, reason: `Necesitas ${reward.cost - participant.points} puntos más` };
    }

    participant.points -= reward.cost;
    participant.claimedRewards.push(rewardId);
    saveParticipant(participant);

    return { success: true, participant };
}

// --- Admin Secret ---
export function getAdminSecret() {
    let secret = get(KEYS.ADMIN_SECRET, null);
    if (!secret) {
        secret = generateId() + generateId();
        set(KEYS.ADMIN_SECRET, secret);
    }
    return secret;
}

// --- Device Fingerprint ---
function getDeviceFingerprint() {
    const nav = navigator;
    const screen = window.screen;
    const raw = [
        nav.userAgent,
        nav.language,
        screen.width + 'x' + screen.height,
        screen.colorDepth,
        Intl.DateTimeFormat().resolvedOptions().timeZone,
        nav.hardwareConcurrency || '',
    ].join('|');

    // Simple hash
    let hash = 0;
    for (let i = 0; i < raw.length; i++) {
        const char = raw.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return Math.abs(hash).toString(36);
}

// --- Seed demo data ---
export function seedDemoData() {
    if (getGroups().length > 0) return;
    const demoGroups = [
        { name: 'IEEE Student Branch', emoji: '⚡', standNumber: 'A-01', description: 'Ingeniería eléctrica y electrónica', visitPoints: 10, activityPoints: 25 },
        { name: 'ACM Chapter', emoji: '💻', standNumber: 'A-02', description: 'Ciencias de la computación y programación', visitPoints: 10, activityPoints: 30 },
        { name: 'Club de Robótica', emoji: '🤖', standNumber: 'B-01', description: 'Diseño y construcción de robots', visitPoints: 15, activityPoints: 35 },
        { name: 'Sociedad de Matemáticas', emoji: '📐', standNumber: 'B-02', description: 'Exploración y divulgación matemática', visitPoints: 10, activityPoints: 20 },
        { name: 'GDG on Campus', emoji: '🌐', standNumber: 'C-01', description: 'Comunidad de developers Google', visitPoints: 10, activityPoints: 25 },
        { name: 'Eco-Club', emoji: '🌱', standNumber: 'C-02', description: 'Sustentabilidad y medio ambiente', visitPoints: 10, activityPoints: 20 },
    ];

    demoGroups.forEach(g => addGroup(g));
}
