import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/AuthContext.jsx';
import { Compass, ScanLine, Star, Gift, ArrowRight } from 'lucide-react';

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
            <div className="welcome-logo" style={{ textAlign: 'center', margin: '2rem 0' }}>
                <img src="/images/logo/LOGO.svg" alt="Logo" style={{ width: '100%', maxWidth: 380, height: 'auto' }} />
            </div>

            <p className="welcome-subtitle">
                Escanea códigos QR, acumula puntos y gana increíbles premios
            </p>

            <div className="welcome-features">
                <div className="welcome-feature" style={{ animationDelay: '0.1s' }}>
                    <div className="feat-icon"><ScanLine size={22} /></div>
                    <div className="feat-text">
                        <strong>Escanea QR</strong>
                        Visita stands y escanea sus códigos
                    </div>
                </div>
                <div className="welcome-feature" style={{ animationDelay: '0.2s' }}>
                    <div className="feat-icon"><Star size={22} /></div>
                    <div className="feat-text">
                        <strong>Acumula Puntos</strong>
                        Gana puntos por visitas y actividades
                    </div>
                </div>
                <div className="welcome-feature" style={{ animationDelay: '0.3s' }}>
                    <div className="feat-icon"><Gift size={22} /></div>
                    <div className="feat-text">
                        <strong>Canjea Premios</strong>
                        Intercambia tus puntos por recompensas
                    </div>
                </div>
            </div>

            <button className="btn btn-primary btn-lg btn-full" onClick={() => navigate('/register')} style={{ maxWidth: 320, margin: '0 auto', display: 'flex' }}>
                <ArrowRight size={18} /> Comenzar
            </button>

            <p style={{ marginTop: 40, fontSize: '0.85rem', color: 'var(--text-secondary)', textAlign: 'center' }}>
                <span style={{ cursor: 'pointer', textDecoration: 'underline', fontWeight: 500 }} onClick={() => navigate('/admin/login')}>
                    Panel de administración →
                </span>
            </p>
        </div>
    );
}
