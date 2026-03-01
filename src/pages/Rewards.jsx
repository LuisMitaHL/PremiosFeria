import React, { useState } from 'react';
import { getRewards, getParticipant, claimReward } from '../lib/storage.js';

export default function Rewards() {
    const [rewards] = useState(getRewards());
    const [participant, setParticipant] = useState(getParticipant());
    const [toast, setToast] = useState(null);

    function handleClaim(rewardId) {
        const result = claimReward(rewardId);
        if (result.success) {
            setParticipant({ ...result.participant });
            setToast({ type: 'success', message: '🎉 ¡Premio reclamado exitosamente!' });
        } else {
            setToast({ type: 'error', message: result.reason });
        }

        setTimeout(() => setToast(null), 3000);
    }

    if (!participant) return null;

    return (
        <div className="page">
            <div className="container">
                <div className="page-header">
                    <h1>🎁 Premios</h1>
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
                        const claimed = participant.claimedRewards.includes(reward.id);
                        const canAfford = participant.points >= reward.cost;

                        return (
                            <div key={reward.id} className={`reward-card ${claimed ? 'claimed' : ''}`}>
                                <div className="reward-emoji">{reward.emoji}</div>
                                <div className="reward-info">
                                    <div className="reward-name">
                                        {reward.name}
                                        {claimed && <span className="badge badge-green" style={{ marginLeft: 8 }}>Canjeado</span>}
                                    </div>
                                    <div className="reward-desc">{reward.description}</div>
                                    <div className="reward-cost">⭐ {reward.cost} pts</div>
                                </div>
                                {!claimed && (
                                    <button
                                        className={`btn ${canAfford ? 'btn-primary' : 'btn-outline'}`}
                                        onClick={() => canAfford && handleClaim(reward.id)}
                                        disabled={!canAfford}
                                        style={{ flexShrink: 0, fontSize: '0.8rem', padding: '8px 16px' }}
                                    >
                                        {canAfford ? 'Canjear' : '🔒'}
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
                        <div className="toast-icon">{toast.type === 'success' ? '✅' : '❌'}</div>
                        <div className="toast-message">{toast.message}</div>
                    </div>
                </div>
            )}
        </div>
    );
}
