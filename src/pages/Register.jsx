import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/AuthContext.jsx';
import { UserPlus, AlertTriangle, Loader, PartyPopper } from 'lucide-react';

export default function Register() {
    const navigate = useNavigate();
    const { participant, registerParticipant } = useAuth();
    const [form, setForm] = useState({ name: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    // If already registered, redirect
    useEffect(() => {
        if (participant) navigate('/dashboard', { replace: true });
    }, [participant, navigate]);

    const handleSubmit = async (e) => {
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
        if (form.name.trim().length > 24) {
            setError('El nombre no puede tener más de 24 caracteres');
            return;
        }

        setLoading(true);
        try {
            await registerParticipant({
                name: form.name.trim()
            });
            navigate('/dashboard', { replace: true });
        } catch (err) {
            setError(err.message || 'Error al registrarse');
            setLoading(false);
        }
    };

    return (
        <div className="page">
            <div className="container" style={{ paddingTop: 60 }}>
                <div style={{ textAlign: 'center', marginBottom: 32 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}><UserPlus size={48} strokeWidth={1.5} /></div>
                    <h1 style={{ fontSize: '1.8rem', fontWeight: 800 }}>Regístrate</h1>
                    <p style={{ color: 'var(--text-secondary)', marginTop: 8 }}>
                        Crea tu cuenta para empezar a acumular puntos
                    </p>
                </div>

                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label">Elige tu nombre</label>
                        <input
                            className="form-input"
                            type="text"
                            placeholder="Ej: zorro"
                            maxLength={24}
                            value={form.name}
                            onChange={e => setForm({ ...form, name: e.target.value })}
                            autoFocus
                        />
                    </div>

                    {error && (
                        <p style={{ color: 'var(--accent-rose)', fontSize: '0.85rem', marginBottom: 16 }}>
                            <AlertTriangle size={14} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} /> {error}
                        </p>
                    )}

                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? <><Loader size={16} className="spin-icon" /> Registrando...</> : <>Registrarme</>}
                    </button>
                </form>

                <p className="register-notes">
                    Con este nombre vuelves a tu perfil si cierras la aplicación, siempre desde
                    este mismo dispositivo. Nadie más puede usarlo.
                </p>
                <p className="register-notes">
                    Elige algo apropiado: un nombre ofensivo te deja sin poder canjear premios.
                </p>
            </div>
        </div>
    );
}
