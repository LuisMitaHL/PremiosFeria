import { useState, useEffect, useCallback } from 'react';
import {
    AlertTriangle,
    CalendarClock,
    Check,
    Clock,
    Hourglass,
    Loader,
    Radio,
    Star,
    Timer,
} from 'lucide-react';
import { useAuth } from '../lib/authContext.js';
import { getAllActivities, getScansForParticipant, startPolling } from '../lib/api.js';
import DynamicIcon from '../components/DynamicIcon.jsx';

// An activity starts and finishes without anything telling this screen, and the
// system has no realtime (ADR 0003), so it asks again while it is open -- the
// same interval the leaderboard uses (spec 025, R11).

// The order of this array is the order of the screen: what can be done now,
// then what is coming, then what is over (spec 025, R3). Nothing here is
// tappable, so a row that changes group between two refreshes cannot move
// under a finger.
const GROUPS = [
    {
        state: 'running',
        title: 'En curso',
        icon: Radio,
        empty: 'Ninguna actividad en curso.',
    },
    {
        state: 'scheduled',
        title: 'Por iniciar',
        icon: Clock,
        empty: null,
    },
    {
        state: 'finished',
        title: 'Terminadas',
        icon: Hourglass,
        empty: null,
    },
];

const STATE_LABEL = {
    scheduled: 'Por iniciar',
    running: 'En curso',
    finished: 'Terminada',
    unavailable: 'No disponible',
};

function formatStart(time) {
    return (time || '').slice(0, 5);
}

// Sin stand legible, o con el stand retirado, la actividad ya no es un lugar
// al que ir (spec 025, R10).
function isReachable(activity) {
    return Boolean(activity.communities) && !activity.communities.is_withdrawn;
}

function ActivityCard({ activity, completed, unavailable }) {
    const state = unavailable ? 'unavailable' : activity.activity_state;
    const stand = activity.communities;
    const className = [
        'glass-card',
        'activity-card',
        `is-${state}`,
        completed ? 'is-completed' : '',
    ]
        .filter(Boolean)
        .join(' ');

    return (
        <article className={className}>
            <div className="activity-head">
                <div className="activity-headings">
                    <div className="activity-name">
                        {activity.name}
                        {activity.is_main_event && (
                            <span className="badge badge-main">
                                <Star size={11} /> Evento principal
                            </span>
                        )}
                    </div>
                    <div className="activity-stand">
                        <span className="activity-stand-icon">
                            <DynamicIcon name={stand?.emoji} size={14} />
                        </span>
                        <span className="activity-stand-name">
                            {stand ? stand.name : 'Stand no disponible'}
                        </span>
                        {stand?.stand_number && (
                            <span className="activity-stand-number">
                                Stand {stand.stand_number}
                            </span>
                        )}
                    </div>
                </div>
                <span className={`badge badge-${state}`}>
                    {state === 'running' && <span className="live-dot" />}
                    {STATE_LABEL[state]}
                </span>
            </div>

            <p className="activity-description">{activity.description}</p>

            <div className="activity-facts">
                <span className="activity-fact">
                    <Timer size={13} /> {activity.duration_min} min
                </span>
                {state === 'scheduled' && (
                    <span className="activity-fact">
                        <CalendarClock size={13} /> Inicia aprox. {formatStart(activity.estimated_start)} h
                    </span>
                )}
                {completed && (
                    <span className="badge badge-green">
                        <Check size={12} /> Completada
                    </span>
                )}
            </div>

            {/* Solo se dirige al estudiante cuando todavía puede hacer algo con
                la actividad. Esta pantalla no otorga nada: los puntos salen de
                escanear el código en el stand (spec 025, R12 y R14). */}
            {state === 'running' && !completed && (
                <p className="activity-hint">Escanea el código en el stand para completarla.</p>
            )}
        </article>
    );
}

export default function Activities() {
    const { participant } = useAuth();
    const [activities, setActivities] = useState([]);
    const [completedIds, setCompletedIds] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    const participantId = participant?.id ?? null;

    const load = useCallback(async () => {
        if (!participantId) return;
        try {
            // Qué actividades completó este estudiante es su propia historia y
            // se lee para el participante de la sesión abierta, nunca para un
            // identificador que esta pantalla reciba (spec 025, sección 7).
            const [all, scans] = await Promise.all([
                getAllActivities(),
                getScansForParticipant(participantId),
            ]);
            setActivities(all);
            setCompletedIds(
                scans
                    .filter((scan) => scan.type === 'activity' && scan.activity_id)
                    .map((scan) => scan.activity_id)
            );
            setError('');
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [participantId]);

    // Pasa al mecanismo comun (spec 028, R4). Tenia su propio intervalo, y esa
    // es exactamente la diferencia que se notaba: un temporizador propio no se
    // entera de que la pestana volvio, y el navegador lo estrangula mientras
    // esta en segundo plano, asi que el telefono que estuvo en el bolsillo
    // mostraba actividades de hace rato.
    useEffect(() => {
        load();
        return startPolling(load);
    }, [load]);

    if (!participant) return null;

    if (loading) {
        return (
            <div className="page">
                <div className="container">
                    <div className="empty-state">
                        <Loader size={28} className="spin-icon" />
                    </div>
                </div>
            </div>
        );
    }

    // Un stand retirado de la feria (spec 023) ya no otorga nada, aunque su
    // actividad siga marcada como en curso. Sus actividades quedan listadas al
    // final y marcadas como no disponibles, en vez de figurar como un lugar al
    // que caminar (spec 025, R10).
    const available = activities.filter((activity) => isReachable(activity));
    const unavailable = activities.filter((activity) => !isReachable(activity));

    return (
        <div className="page">
            <div className="container fair-activities">
                <div className="page-header">
                    <h1>Actividades</h1>
                    <p>Todo lo que ofrecen los stands de la feria.</p>
                </div>

                {error && (
                    <p className="form-error">
                        <AlertTriangle size={14} /> {error}
                    </p>
                )}

                {activities.length === 0 ? (
                    <div className="empty-state">
                        <div className="empty-icon">
                            <CalendarClock size={40} />
                        </div>
                        <p>Todavía no hay actividades publicadas.</p>
                        <p className="empty-hint">
                            Cuando un stand publique la suya, la verás aquí.
                        </p>
                    </div>
                ) : (
                    GROUPS.map((group) => {
                        const rows = available.filter(
                            (activity) => activity.activity_state === group.state
                        );
                        if (rows.length === 0 && !group.empty) return null;
                        const GroupIcon = group.icon;

                        return (
                            <section key={group.state} className="activity-group">
                                <div className="section-title">
                                    <GroupIcon size={16} /> {group.title}
                                </div>
                                {rows.length === 0 ? (
                                    <p className="activity-group-empty">{group.empty}</p>
                                ) : (
                                    rows.map((activity) => (
                                        <ActivityCard
                                            key={activity.id}
                                            activity={activity}
                                            completed={completedIds.includes(activity.id)}
                                        />
                                    ))
                                )}
                            </section>
                        );
                    })
                )}

                {unavailable.length > 0 && (
                    <section className="activity-group">
                        <div className="section-title">
                            <AlertTriangle size={16} /> No disponibles
                        </div>
                        {unavailable.map((activity) => (
                            <ActivityCard
                                key={activity.id}
                                activity={activity}
                                completed={completedIds.includes(activity.id)}
                                unavailable
                            />
                        ))}
                    </section>
                )}
            </div>
        </div>
    );
}
