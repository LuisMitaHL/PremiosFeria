import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/authContext.js';
import { UserPlus, AlertTriangle, Loader, KeyRound } from 'lucide-react';

export default function Register() {
    const navigate = useNavigate();
    const { participant, registerParticipant, recoverParticipant } = useAuth();
    const [form, setForm] = useState({ name: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    // Quien perdió su perfil vuelve con un código que le dieron en el stand de
    // organización (spec 022). Es el otro camino a la misma pantalla.
    const [recovering, setRecovering] = useState(false);
    const [code, setCode] = useState('');

    // If already registered, redirect
    useEffect(() => {
        if (participant) navigate('/dashboard', { replace: true });
    }, [participant, navigate]);

    const handleRecover = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            await recoverParticipant(code);
            navigate('/dashboard', { replace: true });
        } catch (err) {
            setError(err.message);
            setLoading(false);
        }
    };

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
                    <h1 style={{ fontSize: '1.8rem', fontWeight: 800 }}>
                        {recovering ? 'Recupera tu perfil' : 'Regístrate'}
                    </h1>
                    <p style={{ color: 'var(--text-secondary)', marginTop: 8 }}>
                        {recovering
                            ? 'Vuelve a tus puntos en este teléfono'
                            : 'Crea tu cuenta para empezar a acumular puntos'}
                    </p>
                </div>

                {recovering ? (
                    <form onSubmit={handleRecover} className="glass-card">
                        <div className="form-group">
                            <label className="form-label">Código de recuperación</label>
                            <input
                                className="form-input claim-code-input"
                                value={code}
                                maxLength={6}
                                autoComplete="off"
                                placeholder="Ej: A2B3C4"
                                onChange={e => setCode(e.target.value.toUpperCase())}
                                autoFocus
                            />
                            <p className="form-hint">
                                Te lo dan en el stand de organización. Sirve una sola vez y tu
                                perfil pasa a este teléfono.
                            </p>
                        </div>

                        {error && (
                            <p className="form-error">
                                <AlertTriangle size={14} /> {error}
                            </p>
                        )}

                        <button type="submit" className="btn btn-primary btn-full" disabled={loading}>
                            {loading ? <Loader size={16} className="spin-icon" /> : 'Recuperar mi perfil'}
                        </button>
                    </form>
                ) : (
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

                )}

                {!recovering && (
                    <>
                        <p className="register-notes">
                            Con este nombre vuelves a tu perfil si cierras la aplicación, siempre
                            desde este mismo dispositivo. Nadie más puede usarlo.
                        </p>
                        <p className="register-notes">
                            Elige algo apropiado: un nombre ofensivo te deja sin poder canjear
                            premios.
                        </p>
                    </>
                )}

                <button
                    type="button"
                    className="btn btn-ghost btn-full"
                    style={{ marginTop: 16 }}
                    onClick={() => {
                        setRecovering(!recovering);
                        setError('');
                    }}
                >
                    <KeyRound size={14} />
                    {recovering ? ' Volver a registrarme' : ' Tengo un código de recuperación'}
                </button>
            </div>
        </div>
    );
}
