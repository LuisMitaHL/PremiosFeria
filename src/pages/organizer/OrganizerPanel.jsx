import { useState, useEffect, useCallback, lazy, Suspense } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/authContext.js';
import { getEventOverview } from '../../lib/api.js';
import { LogOut, Loader, AlertTriangle, Activity, TrendingUp } from 'lucide-react';
import CommunitiesArea from './CommunitiesArea.jsx';
import StudentsArea from './StudentsArea.jsx';
import AuditArea from './AuditArea.jsx';
import RewardsArea from './RewardsArea.jsx';

// La pantalla de estadisticas y su libreria de graficos se piden al abrirla:
// asi el paquete que descarga un estudiante no paga por una pantalla que no
// puede ver (spec 031, R5 y ADR 0006).
const StatsArea = lazy(() => import('./StatsArea.jsx'));

const AREAS = [
    ['inicio', 'Inicio'],
    ['estudiantes', 'Estudiantes'],
    ['comunidades', 'Comunidades'],
    ['premios', 'Premios'],
    ['registro', 'Registro'],
    ['estadisticas', 'Estadísticas'],
];

export default function OrganizerPanel() {
    const navigate = useNavigate();
    const { organizerUser, adminLoading, logoutOrganizer } = useAuth();
    const [overview, setOverview] = useState(null);
    const [error, setError] = useState('');
    const [area, setArea] = useState('inicio');

    useEffect(() => {
        if (!adminLoading && !organizerUser) {
            navigate('/organizador/entrar', { replace: true });
        }
    }, [organizerUser, adminLoading, navigate]);

    const load = useCallback(async () => {
        try {
            const data = await getEventOverview();
            // The database refuses a caller it does not recognise as the
            // organiser. Hiding the route is not the control; this is.
            if (data?.error) {
                setError(data.error);
                return;
            }
            setOverview(data);
            setError('');
        } catch (err) {
            setError(err.message);
        }
    }, []);

    useEffect(() => {
        if (!organizerUser) return;
        load();
        const timer = setInterval(load, 10000);
        return () => clearInterval(timer);
    }, [organizerUser, load]);

    async function handleLogout() {
        await logoutOrganizer();
        navigate('/organizador/entrar', { replace: true });
    }

    if (adminLoading || !organizerUser) return null;

    const outOfReach =
        overview?.mostExpensive != null && overview.mostExpensive > overview.maxReachable;

    return (
        <div className="page">
            <div className="container">
                <div className="admin-header">
                    <div>
                        <h1 style={{ fontSize: '1.4rem', fontWeight: 800 }}>Organización</h1>
                        <p className="empty-hint">{organizerUser.username}</p>
                    </div>
                    <button className="btn btn-ghost" onClick={handleLogout}>
                        <LogOut size={14} /> Salir
                    </button>
                </div>

                <div className="section-tabs">
                    {AREAS.map(([key, label]) => (
                        <button
                            key={key}
                            className={`section-tab ${area === key ? 'is-active' : ''}`}
                            onClick={() => setArea(key)}
                        >
                            {label}
                        </button>
                    ))}
                </div>

                {error && (
                    <p className="form-error">
                        <AlertTriangle size={14} /> {error}
                    </p>
                )}

                {area === 'inicio' && !overview && !error && (
                    <div className="empty-state">
                        <Loader size={28} className="spin-icon" />
                    </div>
                )}

                {area === 'inicio' && overview && (
                    <>
                        <div className="stats-grid">
                            <div className="stat-card">
                                <div className="stat-value">{overview.participants}</div>
                                <div className="stat-label">Participantes</div>
                            </div>
                            <div className="stat-card">
                                <div className="stat-value">{overview.pointsAwarded}</div>
                                <div className="stat-label">Puntos otorgados</div>
                            </div>
                            <div className="stat-card">
                                <div className="stat-value">{overview.pointsSpent}</div>
                                <div className="stat-label">Puntos gastados</div>
                            </div>
                            <div className="stat-card">
                                <div className="stat-value">{overview.rewardsHandedOver}</div>
                                <div className="stat-label">Premios entregados</div>
                            </div>
                            <div className="stat-card">
                                <div className="stat-value">{overview.stockRemaining}</div>
                                <div className="stat-label">Unidades por entregar</div>
                            </div>
                            <div className="stat-card">
                                <div className="stat-value">{overview.stands}</div>
                                <div className="stat-label">Stands</div>
                            </div>
                        </div>

                        <div className="section-title">
                            <Activity size={16} /> Ahora mismo
                        </div>
                        {overview.runningActivities.length === 0 ? (
                            <div className="empty-state">
                                <p>Ninguna actividad en curso.</p>
                            </div>
                        ) : (
                            // La clave es stand + actividad y no el indice: la
                            // lista cambia sola conforme los stands inician y
                            // terminan, y con el indice React reutiliza la
                            // tarjeta equivocada. El par es unico porque un
                            // stand tiene como mucho una actividad en curso
                            // (spec 019, indice unico parcial).
                            overview.runningActivities.map((a) => (
                                <div key={`${a.stand}::${a.activity}`} className="glass-card activity-card is-running">
                                    <div className="activity-head">
                                        <div className="activity-name">{a.activity}</div>
                                        <span className="badge badge-running">En curso</span>
                                    </div>
                                    <div className="activity-meta">{a.stand}</div>
                                </div>
                            ))
                        )}

                        <div className="section-title">
                            <TrendingUp size={16} /> ¿Cierra la economía?
                        </div>
                        <div className="glass-card">
                            {overview.rewardsPublished === 0 ? (
                                <p>Todavía no hay premios publicados.</p>
                            ) : (
                                <>
                                    <p>
                                        El premio más caro cuesta{' '}
                                        <strong>{overview.mostExpensive} pts</strong>. Un estudiante
                                        que recorra toda la feria y participe en todo llega a{' '}
                                        <strong>{overview.maxReachable} pts</strong>.
                                    </p>
                                    {outOfReach && (
                                        <p className="form-error" style={{ marginTop: 12 }}>
                                            <AlertTriangle size={14} /> El premio más caro está
                                            fuera de alcance: nadie va a poder reclamarlo.
                                        </p>
                                    )}
                                </>
                            )}
                        </div>
                    </>
                )}

                {area === 'comunidades' && <CommunitiesArea />}

                {area === 'estudiantes' && <StudentsArea />}

                {area === 'registro' && <AuditArea />}

                {area === 'premios' && <RewardsArea />}

                {area === 'estadisticas' && (
                    <Suspense fallback={<div className="empty-state"><Loader size={28} className="spin-icon" /></div>}>
                        <StatsArea />
                    </Suspense>
                )}
            </div>
        </div>
    );
}
