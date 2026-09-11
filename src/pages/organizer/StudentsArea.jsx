import { useState, useEffect, useCallback, useId, useRef } from 'react';
import {
    Search, KeyRound, Pencil, Ban, RotateCcw, Loader, AlertTriangle, Copy, Plus, Minus,
} from 'lucide-react';
import {
    organizerListParticipants,
    startPolling,
    organizerIssueRecoveryCode,
    organizerParticipantDetail,
    organizerRenameParticipant,
    organizerSetParticipantFlags,
    organizerAdjustPoints,
} from '../../lib/api.js';

export default function StudentsArea() {
    const [students, setStudents] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [query, setQuery] = useState('');
    const [selected, setSelected] = useState(null);
    const [detail, setDetail] = useState(null);
    const [recovery, setRecovery] = useState(null);
    const [newName, setNewName] = useState('');
    const [adjust, setAdjust] = useState({ amount: '', reason: '' });
    // Las etiquetas del detalle viven dentro de un .map(), pero solo se dibuja el
    // panel del estudiante seleccionado, así que un identificador por componente
    // alcanza: nunca hay dos copias del mismo id en la página.
    const campoId = useId();

    // Un refresco que falla no tapa la lista ya cargada (spec 028, R6).
    const hubo = useRef(false);

    const load = useCallback(async () => {
        try {
            setStudents(await organizerListParticipants());
            hubo.current = true;
        } catch (err) {
            if (!hubo.current) setError(err.message);
        } finally {
            setLoading(false);
        }
    }, []);

    // Lo que se lee aca lo cambia otra gente, asi que la pantalla se relee sola
    // y tambien al volver a ella (spec 028, R1 y R2). El navegador estrangula
    // los temporizadores en segundo plano, asi que un intervalo por si solo
    // deja vieja justamente la pestana que alguien retoma.
    // El panel de un estudiante abierto se identifica por su id, asi que releer
    // la lista por debajo no lo cierra ni pierde lo escrito (R7).
    useEffect(() => {
        load();
        return startPolling(load);
    }, [load]);

    async function open(student) {
        setSelected(student);
        setNewName(student.name);
        setAdjust({ amount: '', reason: '' });
        setRecovery(null);
        setError('');
        setDetail(null);
        try {
            const result = await organizerParticipantDetail(student.id);
            if (result?.error) {
                setError(result.error);
                return;
            }
            setDetail(result);
        } catch (err) {
            setError(err.message);
        }
    }

    async function run(fn) {
        setError('');
        try {
            const result = await fn();
            if (result?.error) {
                setError(result.error);
                return null;
            }
            await load();
            if (selected) {
                const fresh = await organizerParticipantDetail(selected.id);
                if (!fresh?.error) {
                    setDetail(fresh);
                    setSelected(fresh.participant);
                }
            }
            return result;
        } catch (err) {
            setError(err.message);
            return null;
        }
    }

    if (loading) {
        return (
            <div className="empty-state">
                <Loader size={28} className="spin-icon" />
            </div>
        );
    }

    const filtered = query.trim()
        ? students.filter((s) => s.name.toLowerCase().includes(query.trim().toLowerCase()))
        : students;

    return (
        <div>
            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            {recovery && (
                <div className="glass-card credentials-card">
                    <h3>Código para {recovery.name}</h3>
                    <p className="empty-hint">
                        Díctaselo. Sirve una sola vez y vence en diez minutos. Al usarlo, su perfil
                        pasa al teléfono donde lo escriba y deja de estar en el anterior.
                    </p>
                    <div className="credentials-value">
                        <span>{recovery.code}</span>
                    </div>
                    <div className="activity-actions">
                        <button
                            className="btn btn-ghost"
                            onClick={() => navigator.clipboard?.writeText(recovery.code)}
                        >
                            <Copy size={14} /> Copiar
                        </button>
                        <button className="btn btn-primary" onClick={() => setRecovery(null)}>
                            Listo
                        </button>
                    </div>
                </div>
            )}

            <div className="form-group">
                <label className="form-label" htmlFor={`${campoId}-buscar`}>
                    <Search size={13} /> Buscar por nombre
                </label>
                <input
                    id={`${campoId}-buscar`}
                    className="form-input"
                    value={query}
                    placeholder="Ej: zorro"
                    onChange={(e) => setQuery(e.target.value)}
                />
            </div>

            {filtered.length === 0 && (
                <div className="empty-state">
                    <p>Ningún estudiante coincide.</p>
                </div>
            )}

            {filtered.slice(0, 40).map((student) => (
                <div
                    key={student.id}
                    className={`glass-card activity-card ${student.is_removed ? 'is-finished' : ''}`}
                >
                    <div className="activity-head">
                        <div className="activity-name">{student.name}</div>
                        <span className="badge badge-scheduled">{student.points} pts</span>
                    </div>

                    <div className="activity-meta">
                        {student.is_removed && 'Retirado del evento. '}
                        {student.claims_barred && !student.is_removed && 'No puede canjear premios. '}
                        {!student.is_removed && !student.claims_barred && 'Activo'}
                    </div>

                    <div className="activity-actions">
                        <button className="btn btn-ghost" onClick={() => open(student)}>
                            Ver y gestionar
                        </button>
                    </div>

                    {selected?.id === student.id && (
                        <div className="student-detail">
                            {!detail && <Loader size={20} className="spin-icon" />}

                            {detail && (
                                <>
                                    <div className="form-group">
                                        {/* Encabeza un botón, no un campo: no hay control al
                                            que asociar una etiqueta. */}
                                        <span className="form-label">Recuperar su perfil</span>
                                        <p className="form-hint">
                                            Solo si estás seguro de que es esta persona. El sistema
                                            no puede distinguir a quien cambió de teléfono de quien
                                            quiere el perfil ajeno; vos sí.
                                        </p>
                                        <button
                                            className="btn btn-ghost"
                                            onClick={async () => {
                                                const r = await run(() =>
                                                    organizerIssueRecoveryCode(student.id)
                                                );
                                                if (r?.code) setRecovery(r);
                                            }}
                                        >
                                            <KeyRound size={14} /> Generar código
                                        </button>
                                    </div>

                                    <div className="form-group">
                                        <label className="form-label" htmlFor={`${campoId}-nombre`}>Nombre</label>
                                        <div className="activity-actions">
                                            <input
                                                id={`${campoId}-nombre`}
                                                className="form-input"
                                                value={newName}
                                                maxLength={24}
                                                onChange={(e) => setNewName(e.target.value)}
                                            />
                                            <button
                                                className="btn btn-ghost"
                                                onClick={() =>
                                                    run(() =>
                                                        organizerRenameParticipant(student.id, newName)
                                                    )
                                                }
                                            >
                                                <Pencil size={14} /> Cambiar
                                            </button>
                                        </div>
                                    </div>

                                    <div className="form-group">
                                        <label className="form-label" htmlFor={`${campoId}-monto`}>Ajustar puntos</label>
                                        <p className="form-hint">
                                            Es el único cambio de saldo que no ocurrió en el salón,
                                            así que lleva motivo.
                                        </p>
                                        <div className="activity-actions">
                                            <input
                                                id={`${campoId}-monto`}
                                                className="form-input"
                                                type="number"
                                                placeholder="Ej: 30 o -20"
                                                value={adjust.amount}
                                                style={{ maxWidth: 120 }}
                                                onChange={(e) =>
                                                    setAdjust({ ...adjust, amount: e.target.value })
                                                }
                                            />
                                            {/* La etiqueta visible del grupo nombra al monto,
                                                así que el motivo lleva la suya propia. */}
                                            <input
                                                className="form-input"
                                                aria-label="Motivo del ajuste"
                                                placeholder="Motivo"
                                                value={adjust.reason}
                                                maxLength={200}
                                                onChange={(e) =>
                                                    setAdjust({ ...adjust, reason: e.target.value })
                                                }
                                            />
                                            <button
                                                className="btn btn-ghost"
                                                onClick={async () => {
                                                    const r = await run(() =>
                                                        organizerAdjustPoints(
                                                            student.id,
                                                            adjust.amount,
                                                            adjust.reason
                                                        )
                                                    );
                                                    if (r) setAdjust({ amount: '', reason: '' });
                                                }}
                                            >
                                                {Number(adjust.amount) < 0 ? (
                                                    <Minus size={14} />
                                                ) : (
                                                    <Plus size={14} />
                                                )}{' '}
                                                Aplicar
                                            </button>
                                        </div>
                                    </div>

                                    <div className="activity-actions">
                                        <button
                                            className="btn btn-ghost"
                                            onClick={() =>
                                                run(() =>
                                                    organizerSetParticipantFlags(student.id, {
                                                        claimsBarred: !student.claims_barred,
                                                    })
                                                )
                                            }
                                        >
                                            <Ban size={14} />
                                            {student.claims_barred
                                                ? ' Permitir canjes'
                                                : ' Bloquear canjes'}
                                        </button>
                                        <button
                                            className="btn btn-ghost"
                                            onClick={() =>
                                                run(() =>
                                                    organizerSetParticipantFlags(student.id, {
                                                        removed: !student.is_removed,
                                                    })
                                                )
                                            }
                                        >
                                            {student.is_removed ? (
                                                <>
                                                    <RotateCcw size={14} /> Reincorporar
                                                </>
                                            ) : (
                                                <>
                                                    <Ban size={14} /> Retirar del evento
                                                </>
                                            )}
                                        </button>
                                    </div>

                                    <div className="section-title">Historial</div>
                                    {detail.scans.length === 0 && detail.claims.length === 0 && (
                                        <p className="empty-hint">Todavía no hizo nada.</p>
                                    )}
                                    <ul className="student-history">
                                        {detail.adjustments.map((a, i) => (
                                            <li key={`a${i}`}>
                                                <strong>
                                                    {a.amount > 0 ? '+' : ''}
                                                    {a.amount} pts
                                                </strong>{' '}
                                                ajuste — {a.reason}
                                            </li>
                                        ))}
                                        {detail.claims.map((c, i) => (
                                            <li key={`c${i}`}>
                                                <strong>-{c.cost} pts</strong> {c.reward}
                                                {c.stand ? ` en ${c.stand}` : ''}
                                            </li>
                                        ))}
                                        {detail.scans.slice(0, 15).map((s, i) => (
                                            <li key={`s${i}`}>
                                                <strong>+{s.points} pts</strong>{' '}
                                                {s.type === 'visit' ? 'visita' : s.activity} en{' '}
                                                {s.stand}
                                            </li>
                                        ))}
                                    </ul>
                                </>
                            )}
                        </div>
                    )}
                </div>
            ))}
        </div>
    );
}
