import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/AuthContext.jsx';
import { getCommunities, getScansForParticipant } from '../lib/api.js';

export default function Dashboard() {
    const navigate = useNavigate();
    const { participant, participantLoading, refreshParticipant } = useAuth();

    const [communities, setCommunities] = useState([]);
    const [scanLog, setScanLog] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!participantLoading && !participant) {
            navigate('/', { replace: true });
        }
    }, [participant, participantLoading, navigate]);

    useEffect(() => {
        if (!participant) return;

        const load = async () => {
            try {
                const [comms, scans] = await Promise.all([
                    getCommunities(),
                    getScansForParticipant(participant.id),
                ]);
                setCommunities(comms);
                setScanLog(scans);
            } catch (err) {
                console.error('Dashboard load error:', err);
            } finally {
                setLoading(false);
            }
        };
        load();
    }, [participant]);

    if (participantLoading || !participant) return null;

    // Derive visited stands from scans
    const visitedStandIds = [...new Set(
        scanLog.filter(s => s.type === 'visit').map(s => s.community_id)
    )];
    const activitiesCompletedIds = [...new Set(
        scanLog.filter(s => s.type === 'activity').map(s => s.community_id)
    )];

    const visitedCount = visitedStandIds.length;
    const totalStands = communities.length;
    const activitiesCount = activitiesCompletedIds.length;

    // Count claimed rewards (from scans with negative points could be used, but for now use a simple count)
    const claimedCount = 0; // Will be updated when rewards page is integrated

    function formatTime(ts) {
        const d = new Date(ts);
        const now = new Date();
        const diffMs = now - d;
        const diffMin = Math.floor(diffMs / 60000);

        if (diffMin < 1) return 'Ahora';
        if (diffMin < 60) return `Hace ${diffMin} min`;
        const diffHours = Math.floor(diffMin / 60);
        if (diffHours < 24) return `Hace ${diffHours}h`;
        return d.toLocaleDateString('es');
    }

    return (
        <div className="page">
            <div className="container">
                {/* Points Hero */}
                <div className="points-hero">
                    <div className="points-label">Tus Puntos</div>
                    <div className="points-value">{participant.points}</div>
                    <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginTop: 8 }}>
                        ¡Sigue escaneando para ganar más!
                    </p>
                </div>

                {/* Stats */}
                <div className="stats-grid">
                    <div className="stat-card">
                        <div className="stat-value">{visitedCount}</div>
                        <div className="stat-label">Stands visitados</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value">{totalStands}</div>
                        <div className="stat-label">Total Stands</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value">{activitiesCount}</div>
                        <div className="stat-label">Actividades</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-value">{claimedCount}</div>
                        <div className="stat-label">Premios</div>
                    </div>
                </div>

                {/* Visited Stands */}
                <div className="section-title">📍 Stands</div>
                {communities.length === 0 ? (
                    <div className="empty-state">
                        <div className="empty-icon">🏗️</div>
                        <p>No hay stands registrados aún</p>
                    </div>
                ) : (
                    <div className="stands-visited" style={{ marginBottom: 24 }}>
                        {communities.map(g => {
                            const visited = visitedStandIds.includes(g.id);
                            return (
                                <div key={g.id} className={`stand-chip ${visited ? 'visited' : ''}`}>
                                    <span>{g.emoji}</span>
                                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                        {g.name}
                                    </span>
                                    {visited && <span className="check">✓</span>}
                                </div>
                            );
                        })}
                    </div>
                )}

                {/* Recent Activity */}
                <div className="section-title">📋 Actividad Reciente</div>
                <div className="glass-card" style={{ padding: 0, overflow: 'hidden' }}>
                    {scanLog.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-icon">📸</div>
                            <p>Escanea tu primer QR para comenzar</p>
                        </div>
                    ) : (
                        <ul className="activity-list">
                            {scanLog.slice(0, 10).map((scan, i) => (
                                <li key={scan.id} className="activity-item" style={{ animationDelay: `${i * 0.05}s` }}>
                                    <div className={`activity-icon ${scan.type}`}>
                                        {scan.type === 'visit' ? '📍' : '🎯'}
                                    </div>
                                    <div className="activity-info">
                                        <div className="activity-title">
                                            {scan.communities?.name || 'Stand'}
                                        </div>
                                        <div className="activity-time">
                                            {scan.type === 'visit' ? 'Visita' : 'Actividad'} · {formatTime(scan.created_at)}
                                        </div>
                                    </div>
                                    <div className="activity-points">+{scan.points}</div>
                                </li>
                            ))}
                        </ul>
                    )}
                </div>
            </div>
        </div>
    );
}
