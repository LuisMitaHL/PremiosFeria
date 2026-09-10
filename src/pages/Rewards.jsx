import React, { useState, useEffect } from 'react';
import { useAuth } from '../lib/AuthContext.jsx';
import { getRewards, getClaimedRewards, claimReward } from '../lib/api.js';
import { Gift, Star, Lock, Loader, CheckCircle, XCircle } from 'lucide-react';
import DynamicIcon from '../components/DynamicIcon.jsx';

export default function Rewards() {
    const { participant, refreshParticipant } = useAuth();
    const [rewards, setRewards] = useState([]);
    const [claimedIds, setClaimedIds] = useState([]);
    const [toast, setToast] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!participant) return;

        const load = async () => {
            try {
                const [rewardsData, claimed] = await Promise.all([
                    getRewards(),
                    getClaimedRewards(participant.id),
                ]);
                setRewards(rewardsData);
                setClaimedIds(claimed);
            } catch (err) {
                console.error('Rewards load error:', err);
            } finally {
                setLoading(false);
            }
        };
        load();
    }, [participant]);

    async function handleClaim(rewardId) {
        try {
            const result = await claimReward(rewardId);
            if (result.success) {
                await refreshParticipant();
                setClaimedIds([...claimedIds, rewardId]);
                setToast({ type: 'success', message: '¡Premio reclamado exitosamente!' });
            } else {
                setToast({ type: 'error', message: result.reason });
            }
        } catch (err) {
            setToast({ type: 'error', message: err.message || 'Error al canjear premio' });
        }

        setTimeout(() => setToast(null), 3000);
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
                    <p>Canjea tus puntos por recompensas</p>
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
                </div>

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
                                {!claimed && (
                                    <button
                                        className={`btn ${canClaim ? 'btn-primary' : 'btn-outline'}`}
                                        onClick={() => canClaim && handleClaim(reward.id)}
                                        disabled={!canClaim}
                                        style={{ flexShrink: 0, fontSize: '0.8rem', padding: '8px 16px' }}
                                    >
                                        {canClaim ? 'Canjear' : <Lock size={14} />}
                                    </button>
                                )}
                            </div>
                        );
                    })}
                </div>
            </div>

            {/* Toast */}
            {toast && (
                <div className="toast-container">
                    <div className={`toast ${toast.type}`}>
                        <div className="toast-icon">{toast.type === 'success' ? <CheckCircle size={20} /> : <XCircle size={20} />}</div>
                        <div className="toast-message">{toast.message}</div>
                    </div>
                </div>
            )}
        </div>
    );
}
