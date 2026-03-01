import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getGroups, addGroup, updateGroup, deleteGroup, getParticipantsDB, getScanLog, seedDemoData } from '../../lib/storage.js';

export default function AdminDashboard() {
    const navigate = useNavigate();
    const [groups, setGroups] = useState(getGroups());
    const [showModal, setShowModal] = useState(false);
    const [editingGroup, setEditingGroup] = useState(null);
    const [form, setForm] = useState({ name: '', emoji: '📚', standNumber: '', description: '', visitPoints: 10, activityPoints: 25 });

    const participants = getParticipantsDB();
    const scanLog = getScanLog();

    const totalScans = scanLog.length;
    const totalParticipants = participants.length;
    const totalPoints = participants.reduce((sum, p) => sum + p.points, 0);

    function handleSeedDemo() {
        seedDemoData();
        setGroups(getGroups());
    }

    function openAddModal() {
        setEditingGroup(null);
        setForm({ name: '', emoji: '📚', standNumber: '', description: '', visitPoints: 10, activityPoints: 25 });
        setShowModal(true);
    }

    function openEditModal(group) {
        setEditingGroup(group);
        setForm({
            name: group.name,
            emoji: group.emoji,
            standNumber: group.standNumber,
            description: group.description || '',
            visitPoints: group.visitPoints || 10,
            activityPoints: group.activityPoints || 25,
        });
        setShowModal(true);
    }

    function handleSubmit(e) {
        e.preventDefault();
        if (!form.name.trim()) return;

        if (editingGroup) {
            updateGroup(editingGroup.id, form);
        } else {
            addGroup(form);
        }
        setGroups(getGroups());
        setShowModal(false);
    }

    function handleDelete(id) {
        if (confirm('¿Eliminar este grupo?')) {
            deleteGroup(id);
            setGroups(getGroups());
        }
    }

    const emojis = ['📚', '💻', '⚡', '🤖', '🌐', '🎨', '🔬', '🧪', '📐', '🎮', '🌱', '🎵', '🏋️', '📸', '🚀', '🧠'];

    return (
        <div className="admin-page page">
            <div className="page-header">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <div>
                        <h1>⚙️ Admin</h1>
                        <p>Gestiona grupos y stands</p>
                    </div>
                    <button className="btn btn-outline" onClick={() => navigate('/')} style={{ fontSize: '0.8rem' }}>
                        ← Salir
                    </button>
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
                    <div className="stat-value">{totalPoints}</div>
                    <div className="stat-label">Puntos Dados</div>
                </div>
            </div>

            {/* Actions */}
            <div style={{ display: 'flex', gap: 12, marginBottom: 24 }}>
                <button className="btn btn-primary" onClick={openAddModal} style={{ flex: 1 }}>
                    ➕ Agregar Grupo
                </button>
                {groups.length === 0 && (
                    <button className="btn btn-outline" onClick={handleSeedDemo} style={{ flex: 1 }}>
                        🎲 Demo Data
                    </button>
                )}
            </div>

            {/* Groups List */}
            <div className="section-title">📋 Grupos ({groups.length})</div>

            {groups.length === 0 ? (
                <div className="empty-state">
                    <div className="empty-icon">🏗️</div>
                    <p>No hay grupos registrados. Agrega uno o carga datos de demo.</p>
                </div>
            ) : (
                groups.map(group => (
                    <div key={group.id} className="group-card">
                        <div className="group-header">
                            <div className="group-emoji">{group.emoji}</div>
                            <div>
                                <div className="group-name">{group.name}</div>
                                <div className="group-stand">Stand: {group.standNumber}</div>
                            </div>
                        </div>
                        {group.description && (
                            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 8 }}>
                                {group.description}
                            </p>
                        )}
                        <div className="group-points-config">
                            <div className="point-tag">📍 Visita: {group.visitPoints || 10} pts</div>
                            <div className="point-tag">🎯 Actividad: {group.activityPoints || 25} pts</div>
                        </div>
                        <div className="group-actions">
                            <button
                                className="btn btn-primary"
                                onClick={() => navigate(`/admin/qr/${group.id}`)}
                                style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                            >
                                📱 Mostrar QR
                            </button>
                            <button
                                className="btn btn-outline"
                                onClick={() => openEditModal(group)}
                                style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                            >
                                ✏️ Editar
                            </button>
                            <button
                                className="btn btn-outline"
                                onClick={() => handleDelete(group.id)}
                                style={{ fontSize: '0.8rem', padding: '8px 16px', color: 'var(--accent-rose)' }}
                            >
                                🗑️
                            </button>
                        </div>
                    </div>
                ))
            )}

            {/* Modal */}
            {showModal && (
                <div className="modal-overlay" onClick={() => setShowModal(false)}>
                    <div className="modal-content" onClick={e => e.stopPropagation()}>
                        <div className="modal-header">
                            <h2>{editingGroup ? 'Editar Grupo' : 'Nuevo Grupo'}</h2>
                            <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
                        </div>

                        <form onSubmit={handleSubmit}>
                            <div className="form-group">
                                <label className="form-label">Emoji</label>
                                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                                    {emojis.map(em => (
                                        <button
                                            type="button"
                                            key={em}
                                            onClick={() => setForm({ ...form, emoji: em })}
                                            style={{
                                                fontSize: '1.5rem',
                                                padding: '8px',
                                                borderRadius: 8,
                                                border: form.emoji === em ? '2px solid var(--accent-purple)' : '2px solid transparent',
                                                background: form.emoji === em ? 'rgba(168,85,247,0.15)' : 'var(--bg-glass)',
                                                cursor: 'pointer',
                                            }}
                                        >
                                            {em}
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
                                    value={form.standNumber}
                                    onChange={e => setForm({ ...form, standNumber: e.target.value })}
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

                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                                <div className="form-group">
                                    <label className="form-label">Pts por Visita</label>
                                    <input
                                        className="form-input"
                                        type="number"
                                        min="1"
                                        max="100"
                                        value={form.visitPoints}
                                        onChange={e => setForm({ ...form, visitPoints: parseInt(e.target.value) || 10 })}
                                    />
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Pts por Actividad</label>
                                    <input
                                        className="form-input"
                                        type="number"
                                        min="1"
                                        max="100"
                                        value={form.activityPoints}
                                        onChange={e => setForm({ ...form, activityPoints: parseInt(e.target.value) || 25 })}
                                    />
                                </div>
                            </div>

                            <button type="submit" className="btn btn-primary btn-full">
                                {editingGroup ? '💾 Guardar Cambios' : '➕ Crear Grupo'}
                            </button>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
}
