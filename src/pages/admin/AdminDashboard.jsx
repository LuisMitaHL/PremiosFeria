import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/authContext.js';
import {
    getMyCommunity,
    updateCommunity,
    getScansByCommunity,
    getLeaderboard,
} from '../../lib/api.js';
import { Settings, LogOut, Loader, MapPin, Target, QrCode, Pencil, AlertTriangle, ClipboardList, Save, BookOpen, Monitor, Zap, Bot, Globe, Palette, FlaskConical, TestTube, Ruler, Gamepad2, Sprout, Music, Dumbbell, Camera, Rocket, Brain } from 'lucide-react';
import DynamicIcon from '../../components/DynamicIcon.jsx';
import ActivitiesSection from './ActivitiesSection.jsx';
import RewardsSection from './RewardsSection.jsx';
import ClaimsSection from './ClaimsSection.jsx';

export default function AdminDashboard() {
    const navigate = useNavigate();
    const { adminUser, adminLoading, logoutAdmin } = useAuth();

    const [community, setCommunity] = useState(null);
    const [scans, setScans] = useState([]);
    const [participants, setParticipants] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showModal, setShowModal] = useState(false);
    const [form, setForm] = useState({
        name: '', emoji: 'BookOpen', stand_number: '', description: '',
    });
    // The console has three sections (spec 019, R28). Rewards and claims arrive
    // with specs 021 and 018.
    const [section, setSection] = useState('actividades');

    // Redirect if not authenticated
    useEffect(() => {
        if (!adminLoading && !adminUser) {
            navigate('/admin/login', { replace: true });
        }
    }, [adminUser, adminLoading, navigate]);

    // Load community data
    useEffect(() => {
        if (!adminUser) return;

        const load = async () => {
            try {
                const [comm, allParts] = await Promise.all([
                    getMyCommunity(adminUser.id),
                    getLeaderboard(),
                ]);
                setCommunity(comm);
                setParticipants(allParts);

                if (comm) {
                    const communityScans = await getScansByCommunity(comm.id);
                    setScans(communityScans);
                }
            } catch (err) {
                console.error('Admin load error:', err);
            } finally {
                setLoading(false);
            }
        };
        load();
    }, [adminUser]);

    function openEditModal() {
        if (!community) return;
        setForm({
            name: community.name,
            emoji: community.emoji,
            stand_number: community.stand_number || '',
            description: community.description || '',
        });
        setShowModal(true);
    }

    async function handleSubmit(e) {
        e.preventDefault();
        if (!form.name.trim() || !community) return;

        try {
            const updated = await updateCommunity(community.id, form);
            setCommunity(updated);
            setShowModal(false);
        } catch (err) {
            console.error('Update error:', err);
            alert('Error al actualizar: ' + err.message);
        }
    }

    async function handleLogout() {
        await logoutAdmin();
        navigate('/admin/login', { replace: true });
    }

    const iconOptions = [
        { name: 'BookOpen', icon: BookOpen },
        { name: 'Monitor', icon: Monitor },
        { name: 'Zap', icon: Zap },
        { name: 'Bot', icon: Bot },
        { name: 'Globe', icon: Globe },
        { name: 'Palette', icon: Palette },
        { name: 'FlaskConical', icon: FlaskConical },
        { name: 'TestTube', icon: TestTube },
        { name: 'Ruler', icon: Ruler },
        { name: 'Gamepad2', icon: Gamepad2 },
        { name: 'Sprout', icon: Sprout },
        { name: 'Music', icon: Music },
        { name: 'Dumbbell', icon: Dumbbell },
        { name: 'Camera', icon: Camera },
        { name: 'Rocket', icon: Rocket },
        { name: 'Brain', icon: Brain },
    ];

    if (adminLoading || loading) {
        return (
            <div className="admin-page page">
                <div className="container" style={{ textAlign: 'center', paddingTop: 60 }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}><Loader size={40} className="spin-icon" /></div>
                    <p style={{ color: 'var(--text-secondary)' }}>Cargando panel de administración...</p>
                </div>
            </div>
        );
    }

    if (!adminUser) return null;

    const totalScans = scans.length;
    const totalParticipants = participants.length;
    const communityPoints = scans.reduce((sum, s) => sum + s.points, 0);

    return (
        <div className="admin-page page">
            <div className="page-header">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <div>
                        <h1><Settings size={22} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 8 }} />Admin</h1>
                        <p>{community?.name || 'Panel de administración'}</p>
                    </div>
                    <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-outline" onClick={handleLogout} style={{ fontSize: '0.8rem' }}>
                            <LogOut size={14} /> Salir
                        </button>
                    </div>
                </div>
            </div>

            {/* Stats */}
            <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
                <div className="stat-card">
                    <div className="stat-value">{totalParticipants}</div>
                    <div className="stat-label">Participantes</div>
                </div>
                <div className="stat-card">
                    <div className="stat-value">{totalScans}</div>
                    <div className="stat-label">Escaneos</div>
                </div>
                <div className="stat-card">
                    <div className="stat-value">{communityPoints}</div>
                    <div className="stat-label">Puntos Dados</div>
                </div>
            </div>

            {/* Community Info */}
            {community ? (
                <div className="group-card">
                    <div className="group-header">
                        <div className="group-emoji" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <DynamicIcon name={community.emoji} size={32} />
                        </div>
                        <div>
                            <div className="group-name">{community.name}</div>
                            <div className="group-stand">Stand: {community.stand_number}</div>
                        </div>
                    </div>
                    {community.description && (
                        <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 8 }}>
                            {community.description}
                        </p>
                    )}
                    <div className="group-points-config">
                        <div className="point-tag"><MapPin size={12} /> Visita: 10 pts</div>
                        <div className="point-tag"><Target size={12} /> Evento principal: 30 pts</div>
                        <div className="point-tag"><Target size={12} /> Otras actividades: 10 pts</div>
                    </div>
                    <div className="group-actions">
                        <button
                            className="btn btn-primary"
                            onClick={() => navigate(`/admin/qr/${community.id}`)}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            <QrCode size={14} /> Mostrar QR
                        </button>
                        <button
                            className="btn btn-outline"
                            onClick={openEditModal}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            <Pencil size={14} /> Editar
                        </button>
                    </div>
                </div>
            ) : (
                <div className="empty-state">
                    <div className="empty-icon"><AlertTriangle size={40} /></div>
                    <p>No tienes una comunidad asignada. Contacta al organizador.</p>
                </div>
            )}

            {/* The console's three sections (spec 019, R28). Rewards and claims are
                placeholders until specs 021 and 018. */}
            {community && (
                <>
                    <div className="section-tabs">
                        {[
                            ['actividades', 'Actividades'],
                            ['premios', 'Premios'],
                            ['canjes', 'Canjes'],
                        ].map(([key, label]) => (
                            <button
                                key={key}
                                className={`section-tab ${section === key ? 'is-active' : ''}`}
                                onClick={() => setSection(key)}
                            >
                                {label}
                            </button>
                        ))}
                    </div>

                    {section === 'actividades' && (
                        <ActivitiesSection communityId={community.id} />
                    )}

                    {section === 'premios' && (
                        <RewardsSection communityId={community.id} />
                    )}

                    {section === 'canjes' && (
                        <ClaimsSection communityId={community.id} />
                    )}
                </>
            )}

            {/* Recent Scans */}
            {scans.length > 0 && (
                <>
                    <div className="section-title" style={{ marginTop: 24 }}><ClipboardList size={16} style={{ display: 'inline', verticalAlign: 'middle' }} /> Escaneos recientes ({scans.length})</div>
                    <div className="glass-card" style={{ padding: 0, overflow: 'hidden' }}>
                        <ul className="activity-list">
                            {scans.slice(0, 15).map((scan) => (
                                <li key={scan.id} className="activity-item">
                                    <div className={`activity-icon ${scan.type}`}>
                                        {scan.type === 'visit' ? <MapPin size={18} /> : <Target size={18} />}
                                    </div>
                                    <div className="activity-info">
                                        <div className="activity-title">
                                            {scan.participants?.name || 'Participante'}
                                        </div>
                                        <div className="activity-time">
                                            {scan.type === 'visit' ? 'Visita' : 'Actividad'} · {new Date(scan.created_at).toLocaleTimeString('es')}
                                        </div>
                                    </div>
                                    <div className="activity-points">+{scan.points}</div>
                                </li>
                            ))}
                        </ul>
                    </div>
                </>
            )}

            {/* Edit Modal */}
            {showModal && (
                <div className="modal-overlay" onClick={() => setShowModal(false)}>
                    <div className="modal-content" onClick={e => e.stopPropagation()}>
                        <div className="modal-header">
                            <h2>Editar Comunidad</h2>
                            <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
                        </div>

                        <form onSubmit={handleSubmit}>
                            <div className="form-group">
                                <label className="form-label">Icono</label>
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                                    {iconOptions.map(({ name, icon: Icon }) => (
                                        <button
                                            type="button"
                                            key={name}
                                            onClick={() => setForm({ ...form, emoji: name })}
                                            style={{
                                                fontSize: '1.5rem',
                                                padding: '8px',
                                                borderRadius: 8,
                                                border: form.emoji === name ? '2px solid var(--accent-purple)' : '2px solid transparent',
                                                background: form.emoji === name ? 'rgba(129,0,255,0.1)' : 'var(--bg-glass)',
                                                cursor: 'pointer',
                                                display: 'flex',
                                                alignItems: 'center',
                                                justifyContent: 'center',
                                            }}
                                        >
                                            <Icon size={20} />
                                        </button>
                                    ))}
                                </div>
                            </div>

                            <div className="form-group">
                                <label className="form-label">Nombre del grupo *</label>
                                <input
                                    className="form-input"
                                    type="text"
                                    value={form.name}
                                    onChange={e => setForm({ ...form, name: e.target.value })}
                                    placeholder="Ej: IEEE Student Branch"
                                    required
                                />
                            </div>

                            <div className="form-group">
                                <label className="form-label">Número de Stand</label>
                                <input
                                    className="form-input"
                                    type="text"
                                    value={form.stand_number}
                                    onChange={e => setForm({ ...form, stand_number: e.target.value })}
                                    placeholder="Ej: A-01"
                                />
                            </div>

                            <div className="form-group">
                                <label className="form-label">Descripción</label>
                                <input
                                    className="form-input"
                                    type="text"
                                    value={form.description}
                                    onChange={e => setForm({ ...form, description: e.target.value })}
                                    placeholder="Breve descripción del grupo"
                                />
                            </div>

                            <button type="submit" className="btn btn-primary btn-full">
                                <Save size={16} /> Guardar Cambios
                            </button>
                        </form>
                    </div>
                </div >
            )
            }
        </div >
    );
}
