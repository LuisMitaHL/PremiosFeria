import { useState, useEffect, useCallback, useId, useRef } from 'react';
import { Plus, KeyRound, Pencil, Ban, RotateCcw, Loader, AlertTriangle, Copy } from 'lucide-react';
import {
    getCommunities,
    startPolling,
    organizerCreateCommunity,
    organizerUpdateCommunity,
    organizerResetPassword,
    organizerSetCommunityWithdrawn,
} from '../../lib/api.js';
import DynamicIcon from '../../components/DynamicIcon.jsx';

const ICONS = [
    'BookOpen', 'Shield', 'Cpu', 'Cloud', 'Swords', 'Cat', 'Code', 'Terminal',
    'LayoutGrid', 'Database', 'Bot', 'Camera', 'Rocket', 'Brain', 'Music', 'Sprout',
];

const EMPTY_FORM = { name: '', username: '', stand_number: '', emoji: 'BookOpen', description: '' };

export default function CommunitiesArea() {
    const [communities, setCommunities] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [form, setForm] = useState(EMPTY_FORM);
    const [showForm, setShowForm] = useState(false);
    const [editingId, setEditingId] = useState(null);
    // Shown exactly once, right after it is generated. There is no way back to
    // it: the database keeps only a hash (spec 023, R5).
    const [credentials, setCredentials] = useState(null);
    const campoId = useId();

    // Un refresco que falla no tapa la lista ya cargada (spec 028, R6).
    const hubo = useRef(false);

    const load = useCallback(async () => {
        try {
            setCommunities(await getCommunities());
            hubo.current = true;
        } catch (err) {
            if (!hubo.current) setError(err.message);
        } finally {
            setLoading(false);
        }
    }, []);

    // Lo que se lee aca lo cambia otra gente, asi que la pantalla se relee sola
    // y tambien al volver a ella (spec 028, R1 y R2). El navegador estrangula
    // los temporizadores en segundo plano, asi que un intervalo por si solo
    // deja vieja justamente la pestana que alguien retoma.
    // El formulario a medio llenar y las credenciales recien mostradas viven en
    // su propio estado, asi que releer la lista no los toca (R7).
    useEffect(() => {
        load();
        return startPolling(load);
    }, [load]);

    function openCreate() {
        setEditingId(null);
        setForm(EMPTY_FORM);
        setError('');
        setShowForm(true);
    }

    function openEdit(community) {
        setEditingId(community.id);
        setForm({
            name: community.name,
            username: community.username,
            stand_number: community.stand_number || '',
            emoji: community.emoji || 'BookOpen',
            description: community.description || '',
        });
        setError('');
        setShowForm(true);
    }

    async function handleSubmit(e) {
        e.preventDefault();
        setError('');
        try {
            const result = editingId
                ? await organizerUpdateCommunity(editingId, form)
                : await organizerCreateCommunity(form);
            if (result?.error) {
                setError(result.error);
                return;
            }
            if (result.password) {
                setCredentials({ username: form.username.trim().toLowerCase(), password: result.password });
            }
            setShowForm(false);
            await load();
        } catch (err) {
            setError(err.message);
        }
    }

    async function handleReset(community) {
        setError('');
        try {
            const result = await organizerResetPassword(community.id);
            if (result?.error) {
                setError(result.error);
                return;
            }
            setCredentials({ username: result.username, password: result.password });
        } catch (err) {
            setError(err.message);
        }
    }

    async function handleWithdrawn(community, withdrawn) {
        setError('');
        try {
            const result = await organizerSetCommunityWithdrawn(community.id, withdrawn);
            if (result?.error) {
                setError(result.error);
                return;
            }
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

    return (
        <div>
            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            {credentials && (
                <div className="glass-card credentials-card">
                    <h3>Credenciales de {credentials.username}</h3>
                    <p className="empty-hint">
                        Se muestran una sola vez. Cópialas y entrégalas por un canal seguro: no se
                        pueden volver a ver, solo restablecer.
                    </p>
                    <div className="credentials-value">
                        <span>{credentials.username}</span>
                        <span>{credentials.password}</span>
                    </div>
                    <div className="activity-actions">
                        <button
                            className="btn btn-ghost"
                            onClick={() =>
                                navigator.clipboard?.writeText(
                                    `${credentials.username} / ${credentials.password}`
                                )
                            }
                        >
                            <Copy size={14} /> Copiar
                        </button>
                        <button className="btn btn-primary" onClick={() => setCredentials(null)}>
                            Ya las guardé
                        </button>
                    </div>
                </div>
            )}

            {communities.length === 0 && !showForm && (
                <div className="empty-state">
                    <p>Todavía no hay comunidades.</p>
                    <p className="empty-hint">
                        Sin comunidades no hay stands, y sin stands no hay feria.
                    </p>
                </div>
            )}

            {communities.map((community) => (
                <div
                    key={community.id}
                    className={`glass-card activity-card ${community.is_withdrawn ? 'is-finished' : ''}`}
                >
                    <div className="activity-head">
                        <div className="activity-name">
                            <DynamicIcon name={community.emoji} size={20} />
                            {community.name}
                        </div>
                        {community.is_withdrawn ? (
                            <span className="badge badge-finished">Retirada</span>
                        ) : (
                            <span className="badge badge-scheduled">Stand {community.stand_number}</span>
                        )}
                    </div>

                    <div className="activity-meta">Usuario: {community.username}</div>
                    {community.description && (
                        <p className="activity-description">{community.description}</p>
                    )}

                    <div className="activity-actions">
                        <button className="btn btn-ghost" onClick={() => openEdit(community)}>
                            <Pencil size={14} /> Editar
                        </button>
                        <button className="btn btn-ghost" onClick={() => handleReset(community)}>
                            <KeyRound size={14} /> Restablecer contraseña
                        </button>
                        {community.is_withdrawn ? (
                            <button
                                className="btn btn-ghost"
                                onClick={() => handleWithdrawn(community, false)}
                            >
                                <RotateCcw size={14} /> Reincorporar
                            </button>
                        ) : (
                            <button
                                className="btn btn-ghost"
                                onClick={() => handleWithdrawn(community, true)}
                            >
                                <Ban size={14} /> Retirar
                            </button>
                        )}
                    </div>
                </div>
            ))}

            {!showForm && (
                <button className="btn btn-primary btn-full" onClick={openCreate}>
                    <Plus size={16} /> Nueva comunidad
                </button>
            )}

            {showForm && (
                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-nombre`}>Nombre de la comunidad</label>
                        <input
                            id={`${campoId}-nombre`}
                            className="form-input"
                            value={form.name}
                            required
                            onChange={(e) => setForm({ ...form, name: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-usuario`}>Usuario para iniciar sesión</label>
                        <input
                            id={`${campoId}-usuario`}
                            className="form-input"
                            value={form.username}
                            required
                            disabled={editingId !== null}
                            onChange={(e) => setForm({ ...form, username: e.target.value })}
                        />
                        <p className="form-hint">
                            {editingId
                                ? 'No se puede cambiar: es lo que se le entregó al stand en papel.'
                                : 'Una palabra corta y fácil de dictar. No se podrá cambiar después.'}
                        </p>
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-stand`}>Número de stand</label>
                        <input
                            id={`${campoId}-stand`}
                            className="form-input"
                            value={form.stand_number}
                            onChange={(e) => setForm({ ...form, stand_number: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-descripcion`}>Descripción (opcional)</label>
                        <input
                            id={`${campoId}-descripcion`}
                            className="form-input"
                            value={form.description}
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        {/* Encabeza una botonera, no un campo: no hay control al que asociar
                            la etiqueta, así que nombra al grupo. */}
                        <span className="form-label" id={`${campoId}-icono`}>Ícono</span>
                        <div className="icon-grid" role="group" aria-labelledby={`${campoId}-icono`}>
                            {ICONS.map((icon) => (
                                <button
                                    key={icon}
                                    type="button"
                                    aria-label={`Ícono ${icon}`}
                                    aria-pressed={form.emoji === icon}
                                    className={`icon-option ${form.emoji === icon ? 'is-active' : ''}`}
                                    onClick={() => setForm({ ...form, emoji: icon })}
                                >
                                    <DynamicIcon name={icon} size={20} />
                                </button>
                            ))}
                        </div>
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
