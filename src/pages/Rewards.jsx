import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../lib/authContext.js';
import { getRewards, getClaimedRewards, startPolling } from '../lib/api.js';
import ClaimCodeModal from '../components/ClaimCodeModal.jsx';
import { Gift, Star, Lock, Loader, QrCode } from 'lucide-react';
import DynamicIcon from '../components/DynamicIcon.jsx';

export default function Rewards() {
    const { participant, refreshParticipant } = useAuth();
    const [rewards, setRewards] = useState([]);
    const [claimedIds, setClaimedIds] = useState([]);
    const [showCode, setShowCode] = useState(false);
    const [loading, setLoading] = useState(true);

    const participantId = participant?.id;

    const load = useCallback(async () => {
        if (!participantId) return;
        try {
            const [rewardsData, claimed] = await Promise.all([
                getRewards(),
                getClaimedRewards(participantId),
            ]);
            setRewards(rewardsData);
            setClaimedIds(claimed);
        } catch (err) {
            // Una lectura que falla no borra el catalogo que ya se esta
            // mirando: el estudiante esta parado frente a una mesa, y dejarlo
            // sin pantalla por un paquete perdido es peor que mostrarle algo de
            // hace cinco segundos (spec 028, R6).
            console.error('Rewards load error:', err);
        } finally {
            setLoading(false);
        }
    }, [participantId]);

    // El catalogo es de la feria, no de quien lo mira: una comunidad registra un
    // premio en su mesa mientras trescientas personas lo tienen abierto. Antes
    // se leia una sola vez, asi que ese premio no existia hasta recargar
    // (spec 028, R1). Vuelve a leer tambien al volver a la pantalla, que es el
    // caso del telefono que estuvo en el bolsillo: el navegador estrangula los
    // temporizadores en segundo plano.
    useEffect(() => {
        if (!participantId) return;
        load();
        return startPolling(load);
    }, [participantId, load]);

    async function handleClaimed() {
        await refreshParticipant();
        const claimed = await getClaimedRewards(participant.id);
        setClaimedIds(claimed);
        const fresh = await getRewards();
        setRewards(fresh);
    }

    if (!participant) return null;

    if (loading) {
        return (
            <div className="page">
                <div className="container" style={{ textAlign: 'center', paddingTop: 60 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}><Loader size={40} className="spin-icon" /></div>
                    <p style={{ color: 'var(--text-secondary)' }}>Cargando premios...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <div className="container">
                <div className="page-header">
                    <h1><Gift size={24} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 8 }} />Premios</h1>
                    <p>Elige tu premio, acércate al stand y muestra tu código</p>
                </div>

                {/* Points balance */}
                <div className="glass-card" style={{ textAlign: 'center', marginBottom: 24, padding: 20 }}>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                        Tu Balance
                    </div>
                    <div style={{ fontSize: '2.5rem', fontWeight: 900, background: 'var(--gradient-primary)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
                        {participant.points}
                    </div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>puntos disponibles</div>
                    <button
                        className="btn btn-primary btn-full"
                        style={{ marginTop: 16 }}
                        onClick={() => setShowCode(true)}
                    >
                        <QrCode size={16} /> Mostrar mi código de canje
                    </button>
                </div>

                {showCode && (
                    <ClaimCodeModal
                        onClose={() => setShowCode(false)}
                        onClaimed={handleClaimed}
                    />
                )}

                {/* Rewards Grid */}
                <div className="rewards-grid">
                    {rewards.map(reward => {
                        const claimed = claimedIds.includes(reward.id);
                        const canAfford = participant.points >= reward.cost;
                        const inStock = reward.stock > 0;
                        // A withdrawn prize stays visible so it is clear it
                        // existed, but it cannot be claimed (spec 021, R19a).
                        // The refusal that matters is in the database; this only
                        // keeps anyone from crossing the fair for nothing.
                        const withdrawn = reward.is_withdrawn;
                        const canClaim = canAfford && inStock && !withdrawn;

                        return (
                            <div key={reward.id} className={`reward-card ${claimed ? 'claimed' : ''}`}>
                                <div className="reward-emoji" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: inStock ? 1 : 0.5 }}>
                                    <DynamicIcon name={reward.emoji} size={32} />
                                </div>
                                <div className="reward-info">
                                    <div className="reward-name">
                                        {reward.name}
                                        {claimed && <span className="badge badge-green" style={{ marginLeft: 8 }}>Canjeado</span>}
                                        {!inStock && !claimed && !withdrawn && <span className="badge badge-red" style={{ marginLeft: 8, background: 'var(--accent-rose)', color: 'white' }}>Agotado</span>}
                                        {withdrawn && !claimed && <span className="badge badge-finished" style={{ marginLeft: 8 }}>No disponible</span>}
                                    </div>
                                    <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginBottom: 4 }}>
                                        Stand: {reward.communities?.name || 'Desconocido'} · Quedan: {reward.stock}
                                    </div>
                                    <div className="reward-desc">{reward.description}</div>
                                    <div className="reward-cost">
                                        <Star size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 2 }} /> {reward.cost} pts
                                    </div>
                                </div>
                                {!claimed && !canClaim && (
                                    <span className="reward-locked">
                                        <Lock size={14} />
                                        {!canAfford && `Faltan ${reward.cost - participant.points}`}
                                    </span>
                                )}
                            </div>
                        );
                    })}
                </div>
            </div>

        </div>
    );
}
