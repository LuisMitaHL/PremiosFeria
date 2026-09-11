import { useState, useEffect, useCallback, useId, useRef } from 'react';
import { Plus, PackagePlus, Loader, AlertTriangle } from 'lucide-react';
import {
    getRewardsForCommunity,
    createReward,
    startPolling,
    increaseRewardStock,
} from '../../lib/api.js';
import DynamicIcon from '../../components/DynamicIcon.jsx';

const MAX_COST = 300;
const ICONS = [
    'Gift', 'Shirt', 'Box', 'Server', 'Circle', 'Coffee', 'Cpu', 'Book',
    'Headphones', 'Key', 'Sticker', 'Trophy', 'Ticket', 'Backpack', 'Mug', 'Pen',
];

const EMPTY_FORM = { name: '', description: '', cost: 50, stock: 1, emoji: 'Gift' };

export default function RewardsSection({ communityId }) {
    const [rewards, setRewards] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [showForm, setShowForm] = useState(false);
    const [form, setForm] = useState(EMPTY_FORM);
    const [addingTo, setAddingTo] = useState(null);
    const [addAmount, setAddAmount] = useState(1);
    const campoId = useId();

    // Un refresco que falla no tapa la lista que el stand ya esta leyendo: el
    // error solo se muestra si todavia no hay nada que mostrar (spec 028, R6).
    const hubo = useRef(false);

    const load = useCallback(async () => {
        try {
            setRewards(await getRewardsForCommunity(communityId));
            hubo.current = true;
            setError('');
        } catch (err) {
            if (!hubo.current) setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [communityId]);

    // Lo que se lee aca lo cambia otra gente, asi que la pantalla se relee sola
    // y tambien al volver a ella (spec 028, R1 y R2). El navegador estrangula
    // los temporizadores en segundo plano, asi que un intervalo por si solo
    // deja vieja justamente la pestana que alguien retoma.
    // Aca importa por el organizador: si corrige un costo, el stand tiene que
    // dejar de cotizar el viejo sin que nadie le avise.
    useEffect(() => {
        load();
        return startPolling(load);
    }, [load]);

    async function handleCreate(e) {
        e.preventDefault();
        setError('');
        try {
            const result = await createReward(form);
            if (result?.error) {
                setError(result.error);
                return;
            }
            setForm(EMPTY_FORM);
            setShowForm(false);
            await load();
        } catch (err) {
            setError(err.message);
        }
    }

    async function handleAddStock(rewardId) {
        setError('');
        try {
            const result = await increaseRewardStock(rewardId, addAmount);
            if (result?.error) {
                setError(result.error);
                return;
            }
            setAddingTo(null);
            setAddAmount(1);
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

            {rewards.length === 0 && !showForm && (
                <div className="empty-state">
                    <p>Todavía no registraste premios.</p>
                    <p className="empty-hint">
                        Registra lo que trajiste para que aparezca en el catálogo.
                    </p>
                </div>
            )}

            {rewards.map((reward) => (
                <div
                    key={reward.id}
                    className={`glass-card activity-card ${reward.is_withdrawn ? 'is-finished' : ''}`}
                >
                    <div className="activity-head">
                        <div className="activity-name">
                            <DynamicIcon name={reward.emoji} size={20} />
                            {reward.name}
                        </div>
                        <span className="badge badge-scheduled">{reward.cost} pts</span>
                    </div>

                    {reward.description && (
                        <p className="activity-description">{reward.description}</p>
                    )}

                    <div className="activity-meta">
                        {reward.is_withdrawn
                            ? 'Retirado del catálogo por el organizador'
                            : `Quedan ${reward.stock}`}
                    </div>

                    {!reward.is_withdrawn && (
                        <div className="activity-actions">
                            {addingTo === reward.id ? (
                                <>
                                    <input
                                        className="form-input"
                                        type="number"
                                        min={1}
                                        aria-label={`Unidades a agregar a ${reward.name}`}
                                        value={addAmount}
                                        style={{ maxWidth: 90 }}
                                        onChange={(e) => setAddAmount(e.target.value)}
                                    />
                                    <button
                                        className="btn btn-primary"
                                        onClick={() => handleAddStock(reward.id)}
                                    >
                                        Agregar
                                    </button>
                                    <button
                                        className="btn btn-ghost"
                                        onClick={() => setAddingTo(null)}
                                    >
                                        Cancelar
                                    </button>
                                </>
                            ) : (
                                <button
                                    className="btn btn-ghost"
                                    onClick={() => setAddingTo(reward.id)}
                                >
                                    <PackagePlus size={14} /> Agregar stock
                                </button>
                            )}
                        </div>
                    )}
                </div>
            ))}

            <p className="empty-hint">
                El costo se fija al registrar el premio y solo el organizador puede cambiarlo. Tú
                puedes agregar stock, no reducirlo.
            </p>

            {!showForm && (
                <button className="btn btn-primary btn-full" onClick={() => setShowForm(true)}>
                    <Plus size={16} /> Nuevo premio
                </button>
            )}

            {showForm && (
                <form onSubmit={handleCreate} className="glass-card">
                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-nombre`}>Nombre</label>
                        <input
                            id={`${campoId}-nombre`}
                            className="form-input"
                            value={form.name}
                            minLength={3}
                            maxLength={40}
                            required
                            onChange={(e) => setForm({ ...form, name: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-descripcion`}>Descripción (opcional)</label>
                        <input
                            id={`${campoId}-descripcion`}
                            className="form-input"
                            value={form.description}
                            maxLength={100}
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-costo`}>Costo en puntos</label>
                        <input
                            id={`${campoId}-costo`}
                            className="form-input"
                            type="number"
                            min={0}
                            max={MAX_COST}
                            value={form.cost}
                            required
                            onChange={(e) => setForm({ ...form, cost: e.target.value })}
                        />
                        <p className="form-hint">
                            Máximo {MAX_COST}. Por encima de eso nadie llega a canjearlo. No se
                            puede cambiar después.
                        </p>
                    </div>

                    <div className="form-group">
                        <label className="form-label" htmlFor={`${campoId}-unidades`}>Unidades</label>
                        <input
                            id={`${campoId}-unidades`}
                            className="form-input"
                            type="number"
                            min={0}
                            value={form.stock}
                            required
                            onChange={(e) => setForm({ ...form, stock: e.target.value })}
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
                            Registrar
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
