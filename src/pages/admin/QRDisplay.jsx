import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { getGroups } from '../../lib/storage.js';
import { generateQRPayload, getTimeUntilRotation } from '../../lib/qrSecurity.js';

export default function QRDisplay() {
    const { groupId } = useParams();
    const navigate = useNavigate();
    const groups = getGroups();
    const group = groups.find(g => g.id === groupId);

    const [qrType, setQrType] = useState('visit');
    const [qrData, setQrData] = useState('');
    const [timeLeft, setTimeLeft] = useState(30);

    const refreshQR = useCallback(() => {
        if (!group) return;
        const payload = generateQRPayload(group, qrType);
        setQrData(payload);
        setTimeLeft(getTimeUntilRotation());
    }, [group, qrType]);

    // Generate QR on mount and on type change
    useEffect(() => {
        refreshQR();
    }, [refreshQR]);

    // Countdown timer
    useEffect(() => {
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
    }, [refreshQR]);

    if (!group) {
        return (
            <div className="page" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '80vh' }}>
                <div className="empty-state">
                    <div className="empty-icon">❌</div>
                    <p>Grupo no encontrado</p>
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
                        <div style={{ fontSize: '3rem', marginBottom: 8 }}>{group.emoji}</div>
                        <h2 style={{ fontSize: '1.5rem', fontWeight: 800 }}>{group.name}</h2>
                        <p style={{ color: 'var(--text-secondary)' }}>
                            Stand {group.standNumber} · {qrType === 'visit' ? `${group.visitPoints || 10} pts por visita` : `${group.activityPoints || 25} pts por actividad`}
                        </p>
                    </div>

                    {/* QR Code */}
                    <div className="qr-wrapper" style={{ animation: timeLeft <= 5 ? 'pulse 0.5s ease-in-out infinite' : 'none' }}>
                        <QRCodeSVG
                            value={qrData}
                            size={260}
                            level="M"
                            includeMargin={false}
                            fgColor="#1a1333"
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
