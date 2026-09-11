import { useState, useEffect, useCallback, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/authContext.js';
import GuidedTour from '../components/GuidedTour.jsx';
import { TOUR_ESTUDIANTE, PASOS_ESTUDIANTE } from '../lib/tours.js';
import {
    getCommunities,
    getScansForParticipant,
    getParticipantDashboard,
    startPolling,
} from '../lib/api.js';
import {
    AlertTriangle,
    Check,
    ClipboardList,
    Construction,
    Gift,
    MapPin,
    Radio,
    ScanLine,
    Star,
    Target,
} from 'lucide-react';

import DynamicIcon from '../components/DynamicIcon.jsx';

// Cuántos premios están a su alcance tiene cinco respuestas posibles y solo una
// es un número. Cuál de ellas es la suya lo decide la base, que es donde están
// los datos; acá solo vive el texto (spec 013, sección 6).
const REACH_MESSAGE = {
    barred: 'No puedes canjear premios.',
    none_published: 'Todavía no hay premios publicados.',
    all_claimed: 'Ya canjeaste todos los premios a tu alcance.',
    none_available: 'Ningún premio disponible por ahora.',
};

function StatCard({ value, label }) {
    return (
        <div className="stat-card">
            <div className="stat-value">{value}</div>
            <div className="stat-label">{label}</div>
        </div>
    );
}

export default function Dashboard() {
    const navigate = useNavigate();
    const { participant, participantLoading, refreshParticipant } = useAuth();

    // El encabezado de la aplicación dibuja el saldo desde la sesión, así que
    // se relee junto con las cifras: dos saldos distintos en la misma pantalla
    // se leen como una aplicación rota. Va por referencia porque la función
    // cambia de identidad en cada render, y como dependencia reiniciaría el
    // sondeo cada vez.
    const refresh = useRef(refreshParticipant);
    refresh.current = refreshParticipant;

    const [communities, setCommunities] = useState([]);
    const [scanLog, setScanLog] = useState([]);
    const [summary, setSummary] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    const participantId = participant?.id ?? null;

    useEffect(() => {
        if (!participantLoading && !participant) {
            navigate('/', { replace: true });
        }
    }, [participant, participantLoading, navigate]);

    const load = useCallback(async () => {
        if (!participantId) return;
        try {
            // Las cifras vienen de una sola lectura y por eso no pueden
            // contradecirse entre ellas; las dos listas son listas, no cifras,
            // y ya se traían para dibujarse.
            const [comms, scans, figures] = await Promise.all([
                getCommunities(),
                getScansForParticipant(participantId),
                getParticipantDashboard(),
                refresh.current(),
            ]);
            setCommunities(comms);
            setScanLog(scans);
            setSummary(figures);
            setError(figures?.error || '');
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [participantId]);

    // Alguien mira esta pantalla justo después de que le escanearon el código,
    // y un saldo viejo se lee como un escaneo que no funcionó (spec 013, R10).
    // El mismo mecanismo del ranking y del catálogo de actividades: intervalo,
    // más una relectura al volver a la pantalla.
    useEffect(() => {
        load();
        return startPolling(load);
    }, [load]);

    if (participantLoading || !participant) return null;

    // Qué stands visitó es una lista, no una cifra: la usan los chips de abajo.
    const visitedStandIds = [...new Set(
        scanLog.filter(s => s.type === 'visit').map(s => s.community_id)
    )];

    const figures = summary && !summary.error ? summary : null;
    const running = figures?.running ?? [];
    // Mientras no haya respuesta no hay número que enseñar: un cero de relleno
    // es indistinguible de uno real (spec 013, R7).
    const dash = '—';

    function formatTime(ts) {
        const d = new Date(ts);
        const now = new Date();
        const diffMs = now - d;
        const diffMin = Math.floor(diffMs / 60000);

        if (diffMin < 1) return 'Ahora';
        if (diffMin < 60) return `Hace ${diffMin} min`;
        const diffHours = Math.floor(diffMin / 60);
        if (diffHours < 24) return `Hace ${diffHours}h`;
        return d.toLocaleDateString('es');
    }

    function standsValue() {
        if (!figures || figures.standsTotal === 0) return dash;
        return `${figures.standsVisited}/${figures.standsTotal}`;
    }

    function activitiesValue() {
        if (!figures || figures.activitiesPublished === 0) return dash;
        return `${figures.activitiesCompleted}/${figures.activitiesPublished}`;
    }

    function reachBody() {
        if (!figures) return <p className="reach-message">Cargando tu resumen...</p>;
        if (figures.reachState === 'reachable') {
            return (
                <>
                    <div className="reach-count">{figures.rewardsReachable}</div>
                    <div className="reach-unit">
                        {figures.rewardsReachable === 1
                            ? 'premio a tu alcance'
                            : 'premios a tu alcance'}
                    </div>
                </>
            );
        }
        if (figures.reachState === 'short') {
            // "Tu primer premio" solo mientras sea cierto: a quien ya se llevó
            // uno, decirle eso le borra el que tiene en la mochila.
            return (
                <p className="reach-message">
                    Te faltan {figures.pointsToNext} puntos para{' '}
                    {figures.rewardsClaimed > 0 ? 'el siguiente premio' : 'tu primer premio'}.
                </p>
            );
        }
        return <p className="reach-message">{REACH_MESSAGE[figures.reachState]}</p>;
    }

    return (
        <div className="page">
            <div className="container">
                {/* Points Hero */}
                <div className="points-hero" data-tour="puntos">
                    <div className="points-label">Tus Puntos</div>
                    <div className="points-value">{figures ? figures.points : participant.points}</div>
                    <p style={{ color: 'rgba(255, 255, 255, 0.8)', fontSize: '0.85rem', marginTop: 8 }}>
                        ¡Sigue escaneando para ganar más!
                    </p>
                </div>

                {error && (
                    <p className="form-error">
                        <AlertTriangle size={14} /> {error}
                    </p>
                )}

                {/* Premios al alcance */}
                <section className="glass-card reach-card">
                    <span className="reach-icon"><Gift size={22} /></span>
                    <div className="reach-body">
                        {reachBody()}
                        {figures?.rewardsClaimed > 0 && (
                            <p className="reach-note">
                                Ya recibiste {figures.rewardsClaimed}{' '}
                                {figures.rewardsClaimed === 1 ? 'premio' : 'premios'}.
                            </p>
                        )}
                    </div>
                    {figures?.rewardsPublished > 0 && (
                        <Link className="link-more" to="/rewards">Ver premios</Link>
                    )}
                </section>

                {/* Stats */}
                <div className="stats-grid">
                    <StatCard value={standsValue()} label="Stands visitados" />
                    <StatCard value={activitiesValue()} label="Actividades" />
                </div>

                {/* En curso */}
                <div className="section-head">
                    <div className="section-title"><Radio size={16} /> En curso</div>
                    <Link className="link-more" to="/activities">Ver todas</Link>
                </div>
                {running.length === 0 ? (
                    <p className="activity-group-empty">
                        {figures && figures.activitiesPublished === 0
                            ? 'Todavía no hay actividades publicadas.'
                            : 'Ninguna actividad en curso.'}
                    </p>
                ) : (
                    <div className="running-list">
                        {running.map(item => (
                            <article key={item.id} className="glass-card running-row">
                                <span className="running-icon"><DynamicIcon name={item.icon} size={18} /></span>
                                <div className="running-info">
                                    <div className="running-name">
                                        {item.name}
                                        {item.isMainEvent && (
                                            <span className="badge badge-main">
                                                <Star size={11} /> Evento principal
                                            </span>
                                        )}
                                    </div>
                                    <div className="activity-stand">
                                        <span className="activity-stand-name">{item.stand}</span>
                                        {item.standNumber && (
                                            <span className="activity-stand-number">
                                                Stand {item.standNumber}
                                            </span>
                                        )}
                                    </div>
                                </div>
                                {item.completed ? (
                                    <span className="badge badge-green"><Check size={12} /> Completada</span>
                                ) : (
                                    <span className="badge badge-running">
                                        <span className="live-dot" /> En curso
                                    </span>
                                )}
                            </article>
                        ))}
                    </div>
                )}

                {/* Visited Stands */}
                <div className="section-title" style={{ marginTop: 24 }}><MapPin size={16} /> Stands</div>
                {communities.length === 0 ? (
                    <div className="empty-state">
                        <div className="empty-icon"><Construction size={40} /></div>
                        <p>No hay stands registrados aún.</p>
                    </div>
                ) : (
                    <div className="stands-visited" style={{ marginBottom: 24 }}>
                        {communities.map(g => {
                            const visited = visitedStandIds.includes(g.id);
                            return (
                                <div key={g.id} className={`stand-chip ${visited ? 'visited' : ''}`}>
                                    <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                                        <DynamicIcon name={g.emoji} size={16} />
                                    </span>
                                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                        {g.name}
                                    </span>
                                    {visited && <span className="check"><Check size={14} /></span>}
                                </div>
                            );
                        })}
                    </div>
                )}

                {/* Recent Activity */}
                <div className="section-title"><ClipboardList size={16} /> Actividad Reciente</div>
                <div className="glass-card" style={{ padding: 0, overflow: 'hidden' }}>
                    {scanLog.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-icon"><ScanLine size={40} /></div>
                            <p>{loading ? 'Cargando tu actividad...' : 'Escanea el código de un stand para empezar.'}</p>
                        </div>
                    ) : (
                        <ul className="activity-list">
                            {scanLog.slice(0, 10).map((scan, i) => (
                                <li key={scan.id} className="activity-item" style={{ animationDelay: `${i * 0.05}s` }}>
                                    <div className={`activity-icon ${scan.type}`}>
                                        {scan.type === 'visit' ? <MapPin size={18} /> : <Target size={18} />}
                                    </div>
                                    <div className="activity-info">
                                        <div className="activity-title">
                                            {scan.communities?.name || 'Stand'}
                                        </div>
                                        <div className="activity-time">
                                            {scan.type === 'visit' ? 'Visita' : 'Actividad'} · {formatTime(scan.created_at)}
                                        </div>
                                    </div>
                                    <div className="activity-points">+{scan.points}</div>
                                </li>
                            ))}
                        </ul>
                    )}
                </div>
            </div>

            {/* Solo cuando las cifras llegaron: un paso que senala un elemento
                todavia no dibujado apuntaria al vacio (spec 030, R4). */}
            {figures && <GuidedTour nombre={TOUR_ESTUDIANTE} pasos={PASOS_ESTUDIANTE} />}
        </div>
    );
}
