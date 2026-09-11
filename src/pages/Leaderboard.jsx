import { useState, useEffect } from 'react';
import { useAuth } from '../lib/authContext.js';
import { getLeaderboard, startLeaderboardPolling } from '../lib/api.js';
import { Trophy, Loader, Star, Medal } from 'lucide-react';

export default function Leaderboard() {
    const { participant } = useAuth();
    const [leaderboard, setLeaderboard] = useState([]);
    const [loading, setLoading] = useState(true);

    const loadLeaderboard = async () => {
        try {
            const data = await getLeaderboard();
            setLeaderboard(data);
        } catch (err) {
            console.error('Leaderboard error:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadLeaderboard();

        // No realtime service in prod: poll every 5s (+ on tab focus).
        // Gateway microcaches these reads, so the herd costs ~1 query.
        const stop = startLeaderboardPolling(() => {
            loadLeaderboard();
        });

        return () => stop();
    }, []);

    const top3 = leaderboard.slice(0, 3);

    // Reorder top3 for podium display: [2nd, 1st, 3rd]
    const podiumOrder = top3.length >= 3
        ? [top3[1], top3[0], top3[2]]
        : top3;
    const podiumClasses = top3.length >= 3
        ? ['silver', 'gold', 'bronze']
        : ['gold', 'silver', 'bronze'];

    function getInitials(name) {
        return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
    }

    if (loading) {
        return (
            <div className="page">
                <div className="container" style={{ textAlign: 'center', paddingTop: 60 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}><Loader size={40} className="spin-icon" /></div>
                    <p style={{ color: 'var(--text-secondary)' }}>Cargando ranking...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <div className="container">
                <div className="page-header" style={{ textAlign: 'center' }}>
                    <h1><Trophy size={24} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 8 }} />Ranking</h1>
                    <p>Los participantes con más puntos</p>
                </div>

                {leaderboard.length === 0 ? (
                    <div className="empty-state">
                        <div className="empty-icon"><Trophy size={40} /></div>
                        <p>Aún no hay participantes registrados</p>
                    </div>
                ) : (
                    <>
                        {/* Podium */}
                        {top3.length > 0 && (
                            <div className="podium">
                                {podiumOrder.map((p, i) => {
                                    if (!p) return null;
                                    const cls = podiumClasses[i];
                                    return (
                                        <div key={p.id} className={`podium-item ${cls}`}>
                                            <div className="podium-avatar">{getInitials(p.name)}</div>
                                            <div className="podium-name">{p.name}</div>
                                            <div className="podium-bar">
                                                {p.points}
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        )}

                        {/* Full list */}
                        <div className="glass-card" style={{ padding: 0, overflow: 'hidden' }}>
                            <ul className="leaderboard-list">
                                {leaderboard.map((p, i) => {
                                    const isMe = participant && p.id === participant.id;
                                    return (
                                        <li key={p.id} className={`leaderboard-item ${isMe ? 'is-me' : ''}`}>
                                            <div className="lb-rank">
                                                {i === 0 ? <Medal size={16} color="#f59e0b" /> : i === 1 ? <Medal size={16} color="#94a3b8" /> : i === 2 ? <Medal size={16} color="#cd7f32" /> : `#${i + 1}`}
                                            </div>
                                            <div className="lb-avatar">{getInitials(p.name)}</div>
                                            <div className="lb-name">
                                                {p.name}
                                                {isMe && <span className="badge badge-purple" style={{ marginLeft: 8 }}>Tú</span>}
                                            </div>
                                            <div className="lb-points"><Star size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 2 }} /> {p.points}</div>
                                        </li>
                                    );
                                })}
                            </ul>
                        </div>
                    </>
                )}
            </div>
        </div>
    );
}
