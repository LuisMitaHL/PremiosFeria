import { useState, useEffect, useCallback } from 'react';
import { Plus, PackagePlus, Loader, AlertTriangle } from 'lucide-react';
import {
    getRewardsForCommunity,
    createReward,
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

    const load = useCallback(async () => {
        try {
            setRewards(await getRewardsForCommunity(communityId));
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [communityId]);

    useEffect(() => {
        load();
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
                        <label className="form-label">Descripción (opcional)</label>
                        <input
                            className="form-input"
                            value={form.description}
                            maxLength={100}
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Costo en puntos</label>
                        <input
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
                        <label className="form-label">Unidades</label>
                        <input
                            className="form-input"
                            type="number"
                            min={0}
                            value={form.stock}
                            required
                            onChange={(e) => setForm({ ...form, stock: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Ícono</label>
                        <div className="icon-grid">
                            {ICONS.map((icon) => (
                                <button
                                    key={icon}
                                    type="button"
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
