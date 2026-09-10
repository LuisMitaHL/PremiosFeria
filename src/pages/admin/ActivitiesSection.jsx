import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Play, Square, QrCode, Pencil, Plus, Loader, Star, AlertTriangle } from 'lucide-react';
import {
    getActivitiesForCommunity,
    createActivity,
    updateActivity,
    startActivity,
    finishActivity,
} from '../../lib/api.js';

const MAX_ACTIVITIES = 3;
const EMPTY_FORM = {
    name: '',
    description: '',
    estimated_start: '',
    duration_min: 15,
    is_main_event: false,
};

const STATE_LABEL = {
    scheduled: 'Por iniciar',
    running: 'En curso',
    finished: 'Terminada',
};

export default function ActivitiesSection({ communityId }) {
    const navigate = useNavigate();
    const [activities, setActivities] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [busyId, setBusyId] = useState(null);
    const [showForm, setShowForm] = useState(false);
    const [editingId, setEditingId] = useState(null);
    const [form, setForm] = useState(EMPTY_FORM);

    const load = useCallback(async () => {
        try {
            setActivities(await getActivitiesForCommunity(communityId));
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [communityId]);

    useEffect(() => {
        load();
        // An activity finishes on its own when its duration elapses, and that is
        // decided in the database rather than stored (spec 019). Nothing pushes
        // that change here, so the section asks again while it is open.
        const timer = setInterval(load, 5000);
        return () => clearInterval(timer);
    }, [load]);

    async function act(id, fn) {
        setBusyId(id);
        setError('');
        try {
            const result = await fn(id);
            if (result?.error) setError(result.error);
            await load();
        } catch (err) {
            setError(err.message);
        } finally {
            setBusyId(null);
        }
    }

    function openCreate() {
        setEditingId(null);
        setForm(EMPTY_FORM);
        setError('');
        setShowForm(true);
    }

    function openEdit(activity) {
        setEditingId(activity.id);
        setForm({
            name: activity.name,
            description: activity.description,
            estimated_start: (activity.estimated_start || '').slice(0, 5),
            duration_min: activity.duration_min,
            is_main_event: activity.is_main_event,
        });
        setError('');
        setShowForm(true);
    }

    async function handleSubmit(e) {
        e.preventDefault();
        setError('');
        const fields = { ...form, duration_min: Number(form.duration_min) };
        try {
            const result = editingId
                ? await updateActivity(editingId, fields)
                : await createActivity(fields);
            // The database decides; its reason is written for this reader.
            if (result?.error) {
                setError(result.error);
                return;
            }
            setShowForm(false);
            await load();
        } catch (err) {
            setError(err.message);
        }
    }

    if (loading) {
        return (
            <div className="empty-state">
                <Loader size={28} className="spin-icon" />
            </div>
        );
    }

    const atLimit = activities.length >= MAX_ACTIVITIES;

    return (
        <div>
            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            {activities.length === 0 && !showForm && (
                <div className="empty-state">
                    <p>Todavía no creaste actividades.</p>
                    <p className="empty-hint">
                        Puedes crear hasta {MAX_ACTIVITIES} para todo el evento.
                    </p>
                </div>
            )}

            {activities.map((activity) => {
                const state = activity.activity_state;
                return (
                    <div key={activity.id} className={`glass-card activity-card is-${state}`}>
                        <div className="activity-head">
                            <div>
                                <div className="activity-name">
                                    {activity.name}
                                    {activity.is_main_event && (
                                        <span className="badge badge-main">
                                            <Star size={11} /> Evento principal
                                        </span>
                                    )}
                                </div>
                                <div className="activity-meta">
                                    {(activity.estimated_start || '').slice(0, 5)} h ·{' '}
                                    {activity.duration_min} min
                                </div>
                            </div>
                            <span className={`badge badge-${state}`}>{STATE_LABEL[state]}</span>
                        </div>

                        <p className="activity-description">{activity.description}</p>

                        <div className="activity-actions">
                            {state === 'scheduled' && (
                                <>
                                    <button
                                        className="btn btn-primary"
                                        disabled={busyId === activity.id}
                                        onClick={() => act(activity.id, startActivity)}
                                    >
                                        <Play size={14} /> Iniciar
                                    </button>
                                    <button
                                        className="btn btn-ghost"
                                        onClick={() => openEdit(activity)}
                                    >
                                        <Pencil size={14} /> Editar
                                    </button>
                                </>
                            )}

                            {state === 'running' && (
                                <>
                                    <button
                                        className="btn btn-primary"
                                        onClick={() =>
                                            navigate(
                                                `/admin/qr/${communityId}?activity=${activity.id}`
                                            )
                                        }
                                    >
                                        <QrCode size={14} /> Mostrar QR
                                    </button>
                                    <button
                                        className="btn btn-ghost"
                                        disabled={busyId === activity.id}
                                        onClick={() => act(activity.id, finishActivity)}
                                    >
                                        <Square size={14} /> Terminar
                                    </button>
                                </>
                            )}

                            {state === 'finished' && (
                                <span className="activity-closed">
                                    Esta actividad ya terminó y no puede reabrirse.
                                </span>
                            )}
                        </div>
                    </div>
                );
            })}

            {!showForm && (
                <button
                    className="btn btn-primary btn-full"
                    disabled={atLimit}
                    onClick={openCreate}
                >
                    <Plus size={16} /> Nueva actividad
                </button>
            )}

            {atLimit && !showForm && (
                <p className="empty-hint">
                    Ya creaste el máximo de {MAX_ACTIVITIES} actividades. Terminar una no libera el
                    cupo.
                </p>
            )}

            {showForm && (
                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label">Nombre</label>
                        <input
                            className="form-input"
                            value={form.name}
                            minLength={3}
                            maxLength={40}
                            required
                            onChange={(e) => setForm({ ...form, name: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Descripción</label>
                        <input
                            className="form-input"
                            value={form.description}
                            maxLength={100}
                            required
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Hora estimada de inicio</label>
                        <input
                            className="form-input"
                            type="time"
                            value={form.estimated_start}
                            required
                            onChange={(e) => setForm({ ...form, estimated_start: e.target.value })}
                        />
                        <p className="form-hint">
                            Solo informativa: la actividad corre desde que la inicies.
                        </p>
                    </div>

                    <div className="form-group">
                        <label className="form-label">Duración (minutos)</label>
                        <input
                            className="form-input"
                            type="number"
                            min={1}
                            max={60}
                            value={form.duration_min}
                            required
                            onChange={(e) => setForm({ ...form, duration_min: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-checkbox">
                            <input
                                type="checkbox"
                                checked={form.is_main_event}
                                onChange={(e) =>
                                    setForm({ ...form, is_main_event: e.target.checked })
                                }
                            />
                            Es el evento principal del stand
                        </label>
                        <p className="form-hint">
                            El evento principal otorga 30 puntos; el resto, 10. Solo puede haber uno.
                        </p>
                    </div>

                    <div className="activity-actions">
                        <button type="submit" className="btn btn-primary">
                            {editingId ? 'Guardar' : 'Crear'}
                        </button>
                        <button
                            type="button"
                            className="btn btn-ghost"
                            onClick={() => setShowForm(false)}
                        >
                            Cancelar
                        </button>
                    </div>
                </form>
            )}
        </div>
    );
}
