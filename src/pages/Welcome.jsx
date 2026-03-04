import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/AuthContext.jsx';

export default function Welcome() {
    const navigate = useNavigate();
    const { participant, participantLoading } = useAuth();

    // If already registered, redirect to dashboard
    useEffect(() => {
        if (!participantLoading && participant) {
            navigate('/dashboard', { replace: true });
        }
    }, [participant, participantLoading, navigate]);

    return (
        <div className="welcome-page">
            <div className="welcome-logo">🎪</div>
            <h1 className="welcome-title">FeriaPoints</h1>
            <p className="welcome-subtitle">
                Escanea códigos QR, acumula puntos y gana increíbles premios en la feria universitaria
            </p>

            <div className="welcome-features">
                <div className="welcome-feature" style={{ animationDelay: '0.1s' }}>
                    <div className="feat-icon">📸</div>
                    <div className="feat-text">
                        <strong>Escanea QR</strong>
                        Visita stands y escanea sus códigos
                    </div>
                </div>
                <div className="welcome-feature" style={{ animationDelay: '0.2s' }}>
                    <div className="feat-icon">⭐</div>
                    <div className="feat-text">
                        <strong>Acumula Puntos</strong>
                        Gana puntos por visitas y actividades
                    </div>
                </div>
                <div className="welcome-feature" style={{ animationDelay: '0.3s' }}>
                    <div className="feat-icon">🎁</div>
                    <div className="feat-text">
                        <strong>Canjea Premios</strong>
                        Intercambia tus puntos por recompensas
                    </div>
                </div>
            </div>

            <button className="btn btn-primary btn-lg btn-full" onClick={() => navigate('/register')} style={{ maxWidth: 320 }}>
                🚀 Comenzar
            </button>

            <p style={{ marginTop: 24, fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                <span style={{ cursor: 'pointer', textDecoration: 'underline' }} onClick={() => navigate('/admin/login')}>
                    Panel de administración →
                </span>
            </p>
        </div>
    );
}
