import { useState, useEffect, useCallback, useRef } from 'react';
import { ScrollText, Loader, AlertTriangle, Filter, ChevronDown } from 'lucide-react';
import { auditRead, onReturnToScreen } from '../../lib/api.js';

// Los ambitos que el registro usa, traducidos. La lista es fija y completa a
// proposito: sacarla de la base parecia mas honesto, pero significaba que el
// filtro empieza vacio y va apareciendo solo a medida que la feria genera cada
// tipo de asiento, de modo que la opcion que alguien busca puede no estar
// todavia. Un filtro se aprende una vez.
const AMBITOS = {
    scan: 'Escaneos',
    claim: 'Canjes',
    activity: 'Actividades',
    reward: 'Premios',
    community: 'Comunidades',
    participant: 'Estudiantes',
    auth: 'Inicios de sesión',
};

const ACTORES = {
    participant: 'Estudiante',
    stand: 'Stand',
    organizer: 'Organización',
    anonymous: 'Sin sesión',
};

// Se lee en el orden en que alguien lo contaria: que paso, sobre quien. El
// detalle tecnico queda detras de "Ver todo".
const ACCIONES = {
    'participant.register': 'Registro',
    'participant.recover': 'Perfil recuperado',
    'participant.rename': 'Cambio de nombre',
    'participant.set_flags': 'Sanción',
    'participant.adjust_points': 'Ajuste de puntos',
    'participant.issue_recovery': 'Código de recuperación',
    'scan.award': 'Escaneo',
    'claim.issue_code': 'Código de canje',
    'claim.handover': 'Entrega de premio',
    'activity.create': 'Actividad creada',
    'activity.update': 'Actividad editada',
    'activity.start': 'Actividad iniciada',
    'activity.finish': 'Actividad terminada',
    'reward.create': 'Premio registrado',
    'reward.restock': 'Reposición',
    'reward.reprice': 'Cambio de precio',
    'reward.set_stock': 'Stock corregido',
    'reward.withdraw': 'Alta o baja de premio',
    'community.create': 'Comunidad creada',
    'community.update': 'Comunidad editada',
    'community.reset_password': 'Contraseña restablecida',
    'community.set_withdrawn': 'Alta o baja de comunidad',
    'auth.sign_in_failed': 'Inicio de sesión fallido',
};

const RANGOS = [
    ['', 'Todo el evento'],
    ['15', 'Últimos 15 minutos'],
    ['60', 'Última hora'],
    ['480', 'Últimas 8 horas'],
];

function momento(iso) {
    const d = new Date(iso);
    return d.toLocaleTimeString('es-BO', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

// "cost: 200 to 20": el valor anterior es lo que alguien vino a preguntar, asi
// que va al lado del nuevo y no escondido detras de un boton.
function cambio(before, detail) {
    if (!before) return null;
    return Object.keys(before)
        .map((k) => {
            const antes = String(before[k]);
            const ahora = detail && k in detail ? String(detail[k]) : null;
            return ahora === null ? `${k}: ${antes}` : `${k}: ${antes} → ${ahora}`;
        })
        .join(' · ');
}

export default function AuditArea() {
    const [entradas, setEntradas] = useState([]);
    const [cursor, setCursor] = useState(null);
    const [cargando, setCargando] = useState(true);
    const [cargandoMas, setCargandoMas] = useState(false);
    const [error, setError] = useState('');
    const [filtros, setFiltros] = useState({ kind: '', actorKind: '', outcome: '', minutos: '' });
    const [abierta, setAbierta] = useState(null);

    // Cada cambio de filtro empieza una lectura nueva, y la anterior puede
    // llegar despues. Sin esto, una respuesta vieja pisa a la actual y la
    // pantalla muestra lo que ya no se pidio.
    const lectura = useRef(0);

    const cargar = useCallback(async (f) => {
        const mia = ++lectura.current;
        setCargando(true);
        setError('');
        try {
            const res = await auditRead({ ...f, cursor: null });
            if (mia !== lectura.current) return;
            if (res?.error) {
                setError(res.error);
                setEntradas([]);
                return;
            }
            setEntradas(res.entries);
            setCursor(res.nextCursor);
        } catch (err) {
            if (mia === lectura.current) setError(err.message);
        } finally {
            if (mia === lectura.current) setCargando(false);
        }
    }, []);

    useEffect(() => {
        cargar(filtros);
    }, [cargar, filtros]);

    // El registro no se relee cada cinco segundos, a diferencia del resto de
    // las pantallas: se lee renglon por renglon buscando un momento concreto, y
    // reordenarlo bajo los ojos de quien lo lee cuesta mas que lo que cuesta
    // que este algo viejo. Volver a el si es cuando importa (spec 028, R9).
    useEffect(() => onReturnToScreen(() => cargar(filtros)), [cargar, filtros]);

    async function verMas() {
        if (!cursor || cargandoMas) return;
        setCargandoMas(true);
        try {
            const res = await auditRead({ ...filtros, cursor });
            if (res?.error) {
                setError(res.error);
                return;
            }
            setEntradas((previas) => [...previas, ...res.entries]);
            setCursor(res.nextCursor);
        } catch (err) {
            setError(err.message);
        } finally {
            setCargandoMas(false);
        }
    }

    function cambiar(campo, valor) {
        setFiltros((f) => ({ ...f, [campo]: valor }));
    }

    return (
        <div>
            <p className="empty-hint" style={{ marginBottom: 16 }}>
                <ScrollText size={14} /> Lo que el sistema hizo y lo que se negó a hacer. No se
                edita ni se borra, ni siquiera desde acá.
            </p>

            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            <div className="audit-filters">
                <select
                    className="form-input"
                    aria-label="Filtrar por tipo de movimiento"
                    value={filtros.kind}
                    onChange={(e) => cambiar('kind', e.target.value)}
                >
                    <option value="">Todo</option>
                    {Object.entries(AMBITOS).map(([k, label]) => (
                        <option key={k} value={k}>
                            {label}
                        </option>
                    ))}
                </select>

                <select
                    className="form-input"
                    aria-label="Filtrar por quién lo hizo"
                    value={filtros.actorKind}
                    onChange={(e) => cambiar('actorKind', e.target.value)}
                >
                    <option value="">Cualquiera</option>
                    {Object.entries(ACTORES).map(([k, label]) => (
                        <option key={k} value={k}>
                            {label}
                        </option>
                    ))}
                </select>

                <select
                    className="form-input"
                    aria-label="Filtrar por resultado"
                    value={filtros.outcome}
                    onChange={(e) => cambiar('outcome', e.target.value)}
                >
                    <option value="">Todo</option>
                    <option value="ok">Hecho</option>
                    <option value="refused">Rechazado</option>
                </select>

                <select
                    className="form-input"
                    aria-label="Filtrar por período"
                    value={filtros.minutos}
                    onChange={(e) => cambiar('minutos', e.target.value)}
                >
                    {RANGOS.map(([v, label]) => (
                        <option key={v} value={v}>
                            {label}
                        </option>
                    ))}
                </select>
            </div>

            {cargando && (
                <div className="empty-state">
                    <Loader size={28} className="spin-icon" />
                </div>
            )}

            {!cargando && entradas.length === 0 && !error && (
                <div className="empty-state">
                    <p>No hay movimientos que coincidan.</p>
                    <p className="empty-hint">
                        <Filter size={13} /> Prueba con un rango de tiempo más amplio.
                    </p>
                </div>
            )}

            {!cargando &&
                entradas.map((e) => {
                    const detalle = cambio(e.before, e.detail);
                    const desplegada = abierta === e.id;
                    return (
                        <div
                            key={e.id}
                            className={`glass-card audit-row ${e.outcome === 'refused' ? 'is-refused' : ''}`}
                        >
                            <div className="audit-head">
                                <span className="audit-time">{momento(e.at)}</span>
                                <span className="audit-action">{ACCIONES[e.action] || e.action}</span>
                                <span
                                    className={`badge ${e.outcome === 'refused' ? 'badge-finished' : 'badge-running'}`}
                                >
                                    {e.outcome === 'refused' ? 'Rechazado' : 'Hecho'}
                                </span>
                            </div>

                            <div className="activity-meta">
                                {ACTORES[e.actor_kind] || e.actor_kind}
                                {e.subject_label ? ` · ${e.subject_label}` : ''}
                            </div>

                            {e.reason && <p className="audit-reason">{e.reason}</p>}
                            {detalle && <p className="audit-change">{detalle}</p>}

                            {(e.detail || e.before) && (
                                <button
                                    className="btn btn-ghost audit-more"
                                    onClick={() => setAbierta(desplegada ? null : e.id)}
                                >
                                    <ChevronDown size={13} /> {desplegada ? 'Ocultar' : 'Ver todo'}
                                </button>
                            )}

                            {desplegada && (
                                <pre className="audit-raw">
                                    {JSON.stringify({ before: e.before, detail: e.detail }, null, 2)}
                                </pre>
                            )}
                        </div>
                    );
                })}

            {!cargando && cursor && (
                <button className="btn btn-ghost btn-full" onClick={verMas} disabled={cargandoMas}>
                    {cargandoMas ? <Loader size={16} className="spin-icon" /> : 'Ver más'}
                </button>
            )}
        </div>
    );
}
