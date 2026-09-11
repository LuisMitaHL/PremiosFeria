import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/authContext.js';
import { ShieldCheck, AlertTriangle, Loader, ArrowRight } from 'lucide-react';

export default function AdminLogin() {
    const navigate = useNavigate();
    const { adminUser, loginAdmin } = useAuth();
    const [form, setForm] = useState({ username: '', password: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    // If already logged in, redirect to admin
    useEffect(() => {
        if (adminUser) navigate('/admin', { replace: true });
    }, [adminUser, navigate]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');

        if (!form.username.trim() || !form.password.trim()) {
            setError('Completa todos los campos');
            return;
        }

        setLoading(true);
        const result = await loginAdmin(form.username.trim(), form.password.trim());
        setLoading(false);

        if (result.success) {
            navigate('/admin', { replace: true });
        } else {
            console.error("Login attempt failed:", result);
            setError(result.error ? `Error: ${result.error}` : 'Credenciales incorrectas o error de conexión');
        }
    };

    return (
        <div className="page">
            <div className="container" style={{ paddingTop: 60 }}>
                <div style={{ textAlign: 'center', marginBottom: 32 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 24 }}><ShieldCheck size={48} strokeWidth={1.5} /></div>
                    <h1 style={{ fontSize: '1.8rem', fontWeight: 800 }}>Admin Login</h1>
                    <p style={{ color: 'var(--text-secondary)', marginTop: 8 }}>
                        Ingresa las credenciales de tu comunidad
                    </p>
                </div>

                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label">Usuario de comunidad</label>
                        <input
                            className="form-input"
                            type="text"
                            placeholder="meh"
                            value={form.username}
                            onChange={e => setForm({ ...form, username: e.target.value })}
                            autoFocus
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Contraseña</label>
                        <input
                            className="form-input"
                            type="password"
                            placeholder="••••••••"
                            value={form.password}
                            onChange={e => setForm({ ...form, password: e.target.value })}
                        />
                    </div>

                    {error && (
                        <p style={{ color: 'var(--accent-rose)', fontSize: '0.85rem', marginBottom: 16 }}>
                            <AlertTriangle size={14} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} /> {error}
                        </p>
                    )}

                    <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                        {loading ? <><Loader size={16} className="spin-icon" /> Ingresando...</> : <><ArrowRight size={16} /> Ingresar</>}
                    </button>
                </form>

                <p style={{ textAlign: 'center', marginTop: 32, fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                    <span style={{ cursor: 'pointer', textDecoration: 'underline', fontWeight: 500 }} onClick={() => navigate('/')}>
                        ← Volver al inicio
                    </span>
                </p>
            </div>
        </div>
    );
}
