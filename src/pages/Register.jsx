import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { registerParticipant, getParticipant } from '../lib/storage.js';

export default function Register() {
    const navigate = useNavigate();
    const [form, setForm] = useState({ name: '', email: '', universityId: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    // If already registered, redirect
    React.useEffect(() => {
        const p = getParticipant();
        if (p) navigate('/dashboard', { replace: true });
    }, [navigate]);

    const handleSubmit = (e) => {
        e.preventDefault();
        setError('');

        if (!form.name.trim()) {
            setError('Ingresa tu nombre');
            return;
        }
        if (form.name.trim().length < 2) {
            setError('El nombre debe tener al menos 2 caracteres');
            return;
        }

        setLoading(true);

        // Small delay for UX
        setTimeout(() => {
            registerParticipant({
                name: form.name.trim(),
                email: form.email.trim(),
                universityId: form.universityId.trim(),
            });
            navigate('/dashboard', { replace: true });
        }, 500);
    };

    return (
        <div className="page">
            <div className="container" style={{ paddingTop: 60 }}>
                <div style={{ textAlign: 'center', marginBottom: 32 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}>✍️</div>
                    <h1 style={{ fontSize: '1.8rem', fontWeight: 800 }}>Regístrate</h1>
                    <p style={{ color: 'var(--text-secondary)', marginTop: 8 }}>
                        Crea tu cuenta para empezar a acumular puntos
                    </p>
                </div>

                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label">Nombre completo *</label>
                        <input
                            className="form-input"
                            type="text"
                            placeholder="Ej: María García"
                            value={form.name}
                            onChange={e => setForm({ ...form, name: e.target.value })}
                            autoFocus
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Correo (opcional)</label>
                        <input
                            className="form-input"
                            type="email"
                            placeholder="maria@universidad.edu"
                            value={form.email}
                            onChange={e => setForm({ ...form, email: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">ID Universitario (opcional)</label>
                        <input
                            className="form-input"
                            type="text"
                            placeholder="Ej: A12345678"
                            value={form.universityId}
                            onChange={e => setForm({ ...form, universityId: e.target.value })}
                        />
                    </div>

                    {error && (
                        <p style={{ color: 'var(--accent-rose)', fontSize: '0.85rem', marginBottom: 16 }}>
                            ⚠️ {error}
                        </p>
                    )}

                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? '⏳ Registrando...' : '🎉 Registrarme'}
                    </button>
                </form>

                <p style={{ textAlign: 'center', marginTop: 24, fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    Tu información se guarda localmente en tu dispositivo
                </p>
            </div>
        </div>
    );
}
