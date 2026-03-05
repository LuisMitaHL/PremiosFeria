import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '../../lib/AuthContext.jsx';
import { getMyCommunity, getHmacSecret } from '../../lib/api.js';
import { generateQRPayload, getTimeUntilRotation } from '../../lib/qrSecurity.js';

export default function QRDisplay() {
    const { groupId } = useParams();
    const navigate = useNavigate();
    const { adminUser, adminLoading } = useAuth();

    const [community, setCommunity] = useState(null);
    const [secret, setSecret] = useState(null);
    const [qrType, setQrType] = useState('visit');
    const [qrData, setQrData] = useState('');
    const [timeLeft, setTimeLeft] = useState(30);
    const [loading, setLoading] = useState(true);

    // Redirect if not authenticated
    useEffect(() => {
        if (!adminLoading && !adminUser) {
            navigate('/admin/login', { replace: true });
        }
    }, [adminUser, adminLoading, navigate]);

    // Load community and HMAC secret
    useEffect(() => {
        if (!adminUser) return;

        const load = async () => {
            try {
                const [comm, hmacSecret] = await Promise.all([
                    getMyCommunity(adminUser.id),
                    getHmacSecret(),
                ]);
                setCommunity(comm);
                setSecret(hmacSecret);
            } catch (err) {
                console.error('QR load error:', err);
            } finally {
                setLoading(false);
            }
        };
        load();
    }, [adminUser]);

    const refreshQR = useCallback(() => {
        if (!community || !secret) return;
        const payload = generateQRPayload(community, qrType, secret);
        setQrData(payload);
        setTimeLeft(getTimeUntilRotation());
    }, [community, qrType, secret]);

    // Generate QR on mount and on type/community change
    useEffect(() => {
        refreshQR();
    }, [refreshQR]);

    // Countdown timer
    useEffect(() => {
        if (!community || !secret) return;

        const interval = setInterval(() => {
            setTimeLeft(prev => {
                if (prev <= 1) {
                    refreshQR();
                    return 30;
                }
                return prev - 1;
            });
        }, 1000);

        return () => clearInterval(interval);
    }, [refreshQR, community, secret]);

    if (loading || adminLoading) {
        return (
            <div className="page" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '80vh' }}>
                <div className="empty-state">
                    <div className="empty-icon">⏳</div>
                    <p>Cargando...</p>
                </div>
            </div>
        );
    }

    if (!community || community.id !== groupId) {
        return (
            <div className="page" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '80vh' }}>
                <div className="empty-state">
                    <div className="empty-icon">❌</div>
                    <p>No tienes acceso a esta comunidad</p>
                    <button className="btn btn-primary" onClick={() => navigate('/admin')} style={{ marginTop: 16 }}>
                        ← Volver al Admin
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <div className="container">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 0' }}>
                    <button className="btn btn-outline" onClick={() => navigate('/admin')} style={{ fontSize: '0.8rem' }}>
                        ← Admin
                    </button>
                    <div style={{ display: 'flex', gap: 8 }}>
                        <button
                            className={`btn ${qrType === 'visit' ? 'btn-primary' : 'btn-outline'}`}
                            onClick={() => setQrType('visit')}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            📍 Visita
                        </button>
                        <button
                            className={`btn ${qrType === 'activity' ? 'btn-primary' : 'btn-outline'}`}
                            onClick={() => setQrType('activity')}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            🎯 Actividad
                        </button>
                    </div>
                </div>

                <div className="qr-display-fullscreen">
                    {/* Group Info */}
                    <div style={{ marginBottom: 24 }}>
                        <div style={{ fontSize: '3rem', marginBottom: 8 }}>{community.emoji}</div>
                        <h2 style={{ fontSize: '1.5rem', fontWeight: 800 }}>{community.name}</h2>
                        <p style={{ color: 'var(--text-secondary)' }}>
                            Stand {community.stand_number} · {qrType === 'visit' ? `${community.visit_points || 10} pts por visita` : `${community.activity_points || 25} pts por actividad`}
                        </p>
                    </div>

                    {/* QR Code */}
                    <div className="qr-wrapper" style={{ animation: timeLeft <= 5 ? 'pulse 0.5s ease-in-out infinite' : 'none' }}>
                        <QRCodeSVG
                            value={qrData || 'loading'}
                            size={260}
                            level="M"
                            includeMargin={false}
                            fgColor="#000000"
                            bgColor="#ffffff"
                        />
                    </div>

                    {/* Timer */}
                    <div className="qr-timer" style={{ marginBottom: 16 }}>
                        <span>🔄</span>
                        <span style={{ color: timeLeft <= 5 ? 'var(--accent-rose)' : 'var(--text-primary)' }}>
                            {timeLeft}s
                        </span>
                        <div className="qr-timer-bar">
                            <div
                                className="qr-timer-fill"
                                style={{ width: `${(timeLeft / 30) * 100}%`, background: timeLeft <= 5 ? 'var(--gradient-warn)' : 'var(--gradient-primary)' }}
                            />
                        </div>
                    </div>

                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', maxWidth: 300, textAlign: 'center' }}>
                        🔒 El código QR se renueva cada 30 segundos para evitar uso indebido. Muestra esta pantalla a los visitantes.
                    </p>
                </div>
            </div>
        </div>
    );
}
