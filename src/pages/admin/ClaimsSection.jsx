import { useState, useEffect, useCallback, useId } from 'react';
import { Loader, AlertTriangle, CheckCircle } from 'lucide-react';
import { getRewardsForCommunity, confirmHandover } from '../../lib/api.js';
import DynamicIcon from '../../components/DynamicIcon.jsx';

export default function ClaimsSection({ communityId }) {
    const [rewards, setRewards] = useState([]);
    const [loading, setLoading] = useState(true);
    const [code, setCode] = useState('');
    const [rewardId, setRewardId] = useState('');
    const [error, setError] = useState('');
    const [done, setDone] = useState(null);
    const [busy, setBusy] = useState(false);
    const campoId = useId();

    const load = useCallback(async () => {
        try {
            const all = await getRewardsForCommunity(communityId);
            setRewards(all.filter((r) => !r.is_withdrawn));
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }, [communityId]);

    useEffect(() => {
        load();
    }, [load]);

    async function handleConfirm(e) {
        e.preventDefault();
        setError('');
        setDone(null);
        setBusy(true);
        try {
            const result = await confirmHandover(code.trim().toUpperCase(), rewardId);
            if (!result?.success) {
                setError(result?.reason || 'No se pudo confirmar la entrega.');
                return;
            }
            setDone(result);
            setCode('');
            setRewardId('');
            await load();
        } catch (err) {
            setError(err.message);
        } finally {
            setBusy(false);
        }
    }

    if (loading) {
        return (
            <div className="empty-state">
                <Loader size={28} className="spin-icon" />
            </div>
        );
    }

    if (rewards.length === 0) {
        return (
            <div className="empty-state">
                <p>No tienes premios disponibles para entregar.</p>
                <p className="empty-hint">Regístralos en la sección Premios.</p>
            </div>
        );
    }

    return (
        <div>
            {done && (
                <div className="glass-card claim-confirmed">
                    <CheckCircle size={20} />
                    <div>
                        <strong>{done.participant}</strong> recibió {done.reward}.
                        <div className="empty-hint">
                            Se le descontaron {done.cost} puntos. Le quedan {done.newPoints}.
                        </div>
                    </div>
                </div>
            )}

            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            <form onSubmit={handleConfirm} className="glass-card">
                <div className="form-group">
                    <label className="form-label" htmlFor={`${campoId}-codigo`}>Código del estudiante</label>
                    <input
                        id={`${campoId}-codigo`}
                        className="form-input claim-code-input"
                        value={code}
                        maxLength={6}
                        required
                        autoComplete="off"
                        placeholder="Ej: A2B3C4"
                        onChange={(e) => setCode(e.target.value.toUpperCase())}
                    />
                    <p className="form-hint">
                        Se lo muestra en su pantalla. Sirve una sola vez.
                    </p>
                </div>

                <div className="form-group">
                    {/* Encabeza una botonera, no un campo: no hay control al que asociar
                        la etiqueta, así que nombra al grupo. */}
                    <span className="form-label" id={`${campoId}-premio`}>Premio que le vas a entregar</span>
                    <div className="reward-choices" role="group" aria-labelledby={`${campoId}-premio`}>
                        {rewards.map((reward) => (
                            <button
                                key={reward.id}
                                type="button"
                                className={`reward-choice ${rewardId === reward.id ? 'is-active' : ''}`}
                                disabled={reward.stock <= 0}
                                onClick={() => setRewardId(reward.id)}
                            >
                                <DynamicIcon name={reward.emoji} size={18} />
                                <span className="reward-choice-name">{reward.name}</span>
                                <span className="reward-choice-meta">
                                    {reward.cost} pts · quedan {reward.stock}
                                </span>
                            </button>
                        ))}
                    </div>
                </div>

                <button
                    type="submit"
                    className="btn btn-primary btn-full"
                    disabled={busy || !code || !rewardId}
                >
                    {busy ? 'Confirmando...' : 'Confirmar entrega'}
                </button>
                <p className="form-hint">
                    Al confirmar se le descuentan los puntos y sale una unidad del stock. Hazlo
                    cuando ya le entregaste el premio.
                </p>
            </form>
        </div>
    );
}
