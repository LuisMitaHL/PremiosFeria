import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/authContext.js';
import { ShieldCheck, AlertTriangle, Loader } from 'lucide-react';

export default function OrganizerLogin() {
    const navigate = useNavigate();
    const { organizerUser, loginOrganizer } = useAuth();
    const [form, setForm] = useState({ username: '', password: '' });
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (organizerUser) navigate('/organizador', { replace: true });
    }, [organizerUser, navigate]);

    async function handleSubmit(e) {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            const result = await loginOrganizer(form.username.trim(), form.password);
            if (!result.success) {
                setError(result.error);
                return;
            }
            navigate('/organizador', { replace: true });
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }

    return (
        <div className="page">
            <div className="container" style={{ paddingTop: 60 }}>
                <div style={{ textAlign: 'center', marginBottom: 32 }}>
                    <ShieldCheck size={44} strokeWidth={1.5} />
                    <h1 style={{ fontSize: '1.6rem', fontWeight: 800, marginTop: 12 }}>
                        Organización
                    </h1>
                    <p className="empty-hint">Panel del organizador del evento</p>
                </div>

                <form onSubmit={handleSubmit} className="glass-card">
                    <div className="form-group">
                        <label className="form-label">Usuario</label>
                        <input
                            className="form-input"
                            value={form.username}
                            autoComplete="username"
                            required
                            autoFocus
                            onChange={(e) => setForm({ ...form, username: e.target.value })}
                        />
                    </div>

                    <div className="form-group">
                        <label className="form-label">Contraseña</label>
                        <input
                            className="form-input"
                            type="password"
                            value={form.password}
                            autoComplete="current-password"
                            required
                            onChange={(e) => setForm({ ...form, password: e.target.value })}
                        />
                    </div>

                    {error && (
                        <p className="form-error">
                            <AlertTriangle size={14} /> {error}
                        </p>
                    )}

                    <button type="submit" className="btn btn-primary btn-full" disabled={loading}>
                        {loading ? <Loader size={16} className="spin-icon" /> : 'Ingresar'}
                    </button>
                </form>
            </div>
        </div>
    );
}
