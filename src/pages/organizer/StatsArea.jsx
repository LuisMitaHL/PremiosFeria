import { useState, useEffect, useCallback, useRef } from 'react';
import {
    BarChart3, Download, Loader, AlertTriangle, RefreshCw, Clock,
    MapPin, Gift, Users, ShieldAlert, Wand2,
} from 'lucide-react';
import {
    Chart as ChartJS, CategoryScale, LinearScale, BarElement, PointElement,
    LineElement, ArcElement, Tooltip, Legend,
} from 'chart.js';
import { Bar, Line, Doughnut } from 'react-chartjs-2';
import { getEventStatistics, onReturnToScreen } from '../../lib/api.js';
import { toCsv, downloadCsv } from '../../lib/csv.js';

// La libreria de graficos entra solo cuando se abre esta pantalla: StatsArea se
// alcanza por import() dinamico desde el panel, asi que su chunk no viaja en el
// paquete que descarga un estudiante (spec 031, R5 y ADR 0006).
ChartJS.register(
    CategoryScale, LinearScale, BarElement, PointElement, LineElement,
    ArcElement, Tooltip, Legend,
);

const COLOR = {
    purple: '#8100ff',
    orange: '#f5500c',
    cyan: '#06b6d4',
    emerald: '#10b981',
    amber: '#f59e0b',
    rose: '#f43f5e',
};

// El bucket vuelve como hora local del evento en texto ("2026-09-11T10:00").
// Se muestra tal cual: reinterpretarlo con el Date del dispositivo seria
// cambiarle la hora a la feria.
function etiquetaHora(bucket) {
    return bucket ? bucket.slice(11, 16) : '';
}

function horaCompleta(iso) {
    if (!iso) return '—';
    return new Date(iso).toLocaleString('es-BO', {
        day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
    });
}

function momentoDeLectura(iso) {
    if (!iso) return '';
    return new Date(iso).toLocaleTimeString('es-BO', {
        hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
}

function opcionesBar({ horizontal = false, apilado = false } = {}) {
    return {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: horizontal ? 'y' : 'x',
        plugins: { legend: { display: false } },
        scales: {
            x: {
                stacked: apilado && !horizontal,
                beginAtZero: horizontal,
                grid: { display: false },
                ticks: { font: { size: 10 } },
            },
            y: {
                stacked: apilado && !horizontal,
                beginAtZero: true,
                grid: { display: horizontal },
                ticks: { precision: 0, font: { size: 10 } },
            },
        },
    };
}

function opcionesLinea() {
    return {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        elements: { tension: 0.3, pointRadius: 2 },
        scales: {
            x: { grid: { display: false }, ticks: { font: { size: 10 } } },
            y: { beginAtZero: true, ticks: { precision: 0, font: { size: 10 } } },
        },
    };
}

// Un panel es un titulo, un boton de exportar y una figura o su ausencia. La
// exportacion siempre esta, incluso vacia: R45.
function Panel({ titulo, icono, vacio, columnas, filas, nombreCsv, children }) {
    return (
        <section className="stat-panel">
            <div className="stat-panel-head">
                <h3 className="stat-panel-title">{icono}{titulo}</h3>
                <button
                    className="btn btn-ghost stat-export"
                    onClick={() => downloadCsv(nombreCsv, toCsv(columnas, filas))}
                >
                    <Download size={13} /> CSV
                </button>
            </div>
            {vacio ? <p className="stat-empty">{vacio}</p> : children}
        </section>
    );
}

function Tabla({ columnas, filas, vacio }) {
    if (filas.length === 0) return <p className="stat-empty">{vacio}</p>;
    return (
        <div className="stat-table-wrap">
            <table className="stat-table">
                <thead>
                    <tr>{columnas.map((c) => <th key={c.key}>{c.label}</th>)}</tr>
                </thead>
                <tbody>
                    {filas.map((f, i) => (
                        <tr key={f._key ?? i}>
                            {columnas.map((c) => <td key={c.key}>{f[c.key]}</td>)}
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );
}

export default function StatsArea() {
    const [data, setData] = useState(null);
    const [error, setError] = useState('');
    const [cargando, setCargando] = useState(true);
    const [desde, setDesde] = useState('');
    const [hasta, setHasta] = useState('');
    const [aplicado, setAplicado] = useState({ from: '', to: '' });
    // Una lectura vieja puede llegar despues de una nueva. Sin esto, pisa a la
    // actual y la pantalla muestra un filtro que ya no es el pedido. Mismo
    // patron que el registro de actividad (spec 024).
    const lectura = useRef(0);

    const cargar = useCallback(async (filtro) => {
        const mia = ++lectura.current;
        setCargando(true);
        setError('');
        try {
            const res = await getEventStatistics({
                from: filtro.from ? new Date(filtro.from).toISOString() : null,
                to: filtro.to ? new Date(filtro.to).toISOString() : null,
            });
            if (mia !== lectura.current) return;
            if (res?.error) {
                setError(res.error);
                setData(null);
                return;
            }
            setData(res);
        } catch (err) {
            if (mia === lectura.current) setError(err.message);
        } finally {
            if (mia === lectura.current) setCargando(false);
        }
    }, []);

    // Se lee al abrir y al volver a la pantalla; NO hay temporizador. La feria
    // ya termino y una figura que se reordena mientras se lee no aporta nada
    // (R6 a R10).
    useEffect(() => { cargar({ from: '', to: '' }); }, [cargar]);
    useEffect(() => onReturnToScreen(() => cargar(aplicado)), [cargar, aplicado]);

    function aplicar(e) {
        e.preventDefault();
        setAplicado({ from: desde, to: hasta });
        cargar({ from: desde, to: hasta });
    }

    function limpiar() {
        setDesde('');
        setHasta('');
        setAplicado({ from: '', to: '' });
        cargar({ from: '', to: '' });
    }

    if (cargando && !data) {
        return <div className="empty-state"><Loader size={28} className="spin-icon" /></div>;
    }

    if (error) {
        return (
            <p className="form-error"><AlertTriangle size={14} /> {error}</p>
        );
    }

    if (!data) return null;

    const t = data.attendance.timeline;
    const stands = data.stands;
    const rewards = data.rewards;
    const refusals = data.operations.refusals;
    const codigos = data.operations.claimCodes;
    const bands = data.participants.balanceBands;
    const visitados = data.participants.standsVisited;
    const top = data.participants.top;
    const ajustes = data.adjustments;
    const entregasHora = data.handoversPerHour;
    const sinEntregar = rewards.filter((r) => r.handedOver === 0);
    const co = data.callouts;

    const etiquetas = t.map((p) => etiquetaHora(p.bucket));

    const colsTimeline = [
        { key: 'bucket', label: 'Hora' },
        { key: 'visits', label: 'Visitas' },
        { key: 'activities', label: 'Actividades' },
        { key: 'activeParticipants', label: 'Participantes activos' },
        { key: 'registrations', label: 'Registros' },
        { key: 'pointsAwarded', label: 'Puntos otorgados' },
        { key: 'pointsSpent', label: 'Puntos gastados' },
        { key: 'cumulativePointsAwarded', label: 'Puntos acumulados' },
    ];

    const colsStands = [
        { key: 'name', label: 'Stand' },
        { key: 'standNumber', label: 'Número' },
        { key: 'withdrawn', label: 'Retirado' },
        { key: 'visits', label: 'Visitas' },
        { key: 'activities', label: 'Actividades' },
        { key: 'visitPoints', label: 'Puntos por visitas' },
        { key: 'activityPoints', label: 'Puntos por actividades' },
        { key: 'totalPoints', label: 'Puntos totales' },
        { key: 'totalScans', label: 'Escaneos' },
        { key: 'avgPoints', label: 'Promedio' },
    ];

    const colsRewards = [
        { key: 'name', label: 'Premio' },
        { key: 'stand', label: 'Stand' },
        { key: 'cost', label: 'Costo' },
        { key: 'withdrawn', label: 'Retirado' },
        { key: 'handedOver', label: 'Entregados' },
        { key: 'pointsSpent', label: 'Puntos gastados' },
        { key: 'remaining', label: 'Stock restante' },
    ];

    return (
        <div>
            <div className="stat-filter">
                <form onSubmit={aplicar} className="stat-filter-form">
                    <label>
                        Desde
                        <input type="datetime-local" value={desde} onChange={(e) => setDesde(e.target.value)} />
                    </label>
                    <label>
                        Hasta
                        <input type="datetime-local" value={hasta} onChange={(e) => setHasta(e.target.value)} />
                    </label>
                    <button className="btn btn-primary" type="submit">Aplicar</button>
                    <button className="btn btn-ghost" type="button" onClick={limpiar}>Todo el evento</button>
                    <button
                        className="btn btn-ghost"
                        type="button"
                        onClick={() => cargar(aplicado)}
                        title="Volver a leer"
                    >
                        <RefreshCw size={14} className={cargando ? 'spin-icon' : ''} /> Actualizar
                    </button>
                </form>
                <p className="stat-status">
                    <Clock size={13} /> Leído a las {momentoDeLectura(data.generatedAt)} · hora del evento
                </p>
            </div>

            {/* Lo que la pantalla concluye, no solo lo que dibuja (R38). */}
            <div className="stats-callouts">
                <div className="stat-callout">
                    <div className="stat-callout-value">{co.busiestHour ? etiquetaHora(co.busiestHour.bucket) : '—'}</div>
                    <div className="stat-callout-label">Hora más ocupada</div>
                </div>
                <div className="stat-callout">
                    <div className="stat-callout-value">{co.topStandByPoints ? co.topStandByPoints.points : '—'}</div>
                    <div className="stat-callout-label">{co.topStandByPoints ? co.topStandByPoints.stand : 'Sin puntos'}</div>
                </div>
                <div className="stat-callout">
                    <div className="stat-callout-value">
                        {co.mostHandedOverReward ? co.mostHandedOverReward.count : '—'}
                    </div>
                    <div className="stat-callout-label">
                        {co.mostHandedOverReward ? co.mostHandedOverReward.reward : 'Nada entregado'}
                    </div>
                </div>
                <div className="stat-callout">
                    <div className="stat-callout-value">{data.participants.registeredWithoutScan}</div>
                    <div className="stat-callout-label">Registrados sin escanear</div>
                </div>
                <div className="stat-callout">
                    <div className="stat-callout-value">{co.standsWithoutScans.length}</div>
                    <div className="stat-callout-label">
                        {co.standsWithoutScans.length === 0
                            ? 'Todos los stands escanearon'
                            : co.standsWithoutScans.map((s) => s.stand).join(', ')}
                    </div>
                </div>
            </div>

            <div className="stat-mini-cards">
                <div className="stat-mini">
                    <div className="stat-mini-value">{horaCompleta(data.attendance.bounds.firstScan)}</div>
                    <div className="stat-mini-label">Primer escaneo</div>
                </div>
                <div className="stat-mini">
                    <div className="stat-mini-value">{horaCompleta(data.attendance.bounds.lastScan)}</div>
                    <div className="stat-mini-label">Último escaneo</div>
                </div>
                <div className="stat-mini">
                    <div className="stat-mini-value">{data.attendance.bounds.durationMinutes} min</div>
                    <div className="stat-mini-label">Duración efectiva</div>
                </div>
                <div className="stat-mini">
                    <div className="stat-mini-value">{ajustes.total}</div>
                    <div className="stat-mini-label">Puntos por ajustes manuales</div>
                </div>
            </div>

            <div className="stat-panel-grid">
                <Panel
                    titulo="Escaneos por hora" icono={<BarChart3 size={15} />}
                    vacio={t.length === 0 ? 'Sin escaneos en este rango.' : null}
                    columnas={colsTimeline} filas={t} nombreCsv="escaneos-por-hora.csv"
                >
                    <div className="chart-box">
                        <Bar
                            options={opcionesBar({ apilado: true })}
                            data={{
                                labels: etiquetas,
                                datasets: [
                                    { label: 'Visitas', data: t.map((p) => p.visits), backgroundColor: COLOR.purple },
                                    { label: 'Actividades', data: t.map((p) => p.activities), backgroundColor: COLOR.orange },
                                ],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Participantes activos y registros" icono={<Users size={15} />}
                    vacio={t.length === 0 ? 'Sin datos en este rango.' : null}
                    columnas={[
                        { key: 'bucket', label: 'Hora' },
                        { key: 'activeParticipants', label: 'Activos' },
                        { key: 'registrations', label: 'Registros' },
                    ]}
                    filas={t} nombreCsv="participantes-por-hora.csv"
                >
                    <div className="chart-box">
                        <Line
                            options={opcionesLinea()}
                            data={{
                                labels: etiquetas,
                                datasets: [
                                    { label: 'Activos', data: t.map((p) => p.activeParticipants), borderColor: COLOR.cyan, backgroundColor: COLOR.cyan },
                                    { label: 'Registros', data: t.map((p) => p.registrations), borderColor: COLOR.emerald, backgroundColor: COLOR.emerald },
                                ],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Puntos otorgados y gastados" icono={<BarChart3 size={15} />}
                    vacio={t.length === 0 ? 'Sin datos en este rango.' : null}
                    columnas={[
                        { key: 'bucket', label: 'Hora' },
                        { key: 'pointsAwarded', label: 'Otorgados' },
                        { key: 'pointsSpent', label: 'Gastados' },
                    ]}
                    filas={t} nombreCsv="puntos-por-hora.csv"
                >
                    <div className="chart-box">
                        <Line
                            options={opcionesLinea()}
                            data={{
                                labels: etiquetas,
                                datasets: [
                                    { label: 'Otorgados', data: t.map((p) => p.pointsAwarded), borderColor: COLOR.purple, backgroundColor: COLOR.purple },
                                    { label: 'Gastados', data: t.map((p) => p.pointsSpent), borderColor: COLOR.orange, backgroundColor: COLOR.orange },
                                ],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Puntos por stand" icono={<MapPin size={15} />}
                    vacio={stands.length === 0 ? 'Todavía no hay stands.' : null}
                    columnas={colsStands} filas={stands.map((s) => ({ ...s, withdrawn: s.withdrawn ? 'sí' : 'no' }))}
                    nombreCsv="puntos-por-stand.csv"
                >
                    <div className="chart-box">
                        {stands.length === 0 ? null : (
                            <Bar
                                options={opcionesBar({ horizontal: true, apilado: true })}
                                data={{
                                    labels: stands.map((s) => s.name),
                                    datasets: [
                                        { label: 'Visitas', data: stands.map((s) => s.visitPoints), backgroundColor: COLOR.purple },
                                        { label: 'Actividades', data: stands.map((s) => s.activityPoints), backgroundColor: COLOR.orange },
                                    ],
                                }}
                            />
                        )}
                    </div>
                </Panel>

                <Panel
                    titulo="Premios más entregados" icono={<Gift size={15} />}
                    vacio={rewards.length === 0 ? 'Todavía no hay premios publicados.' : 'Ningún premio se entregó todavía.'}
                    columnas={colsRewards} filas={rewards.map((r) => ({ ...r, withdrawn: r.withdrawn ? 'sí' : 'no' }))}
                    nombreCsv="premios.csv"
                >
                    <div className="chart-box">
                        <Bar
                            options={opcionesBar({ horizontal: true })}
                            data={{
                                labels: rewards.map((r) => r.name),
                                datasets: [{ label: 'Entregados', data: rewards.map((r) => r.handedOver), backgroundColor: COLOR.emerald }],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Puntos gastados por premio" icono={<Gift size={15} />}
                    vacio={rewards.length === 0 ? 'Todavía no hay premios publicados.' : null}
                    columnas={[
                        { key: 'name', label: 'Premio' },
                        { key: 'stand', label: 'Stand' },
                        { key: 'pointsSpent', label: 'Puntos gastados' },
                    ]}
                    filas={rewards} nombreCsv="puntos-gastados-por-premio.csv"
                >
                    <div className="chart-box">
                        <Bar
                            options={opcionesBar({ horizontal: true })}
                            data={{
                                labels: rewards.map((r) => r.name),
                                datasets: [{ label: 'Puntos gastados', data: rewards.map((r) => r.pointsSpent), backgroundColor: COLOR.amber }],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Stock entregado y restante" icono={<Gift size={15} />}
                    vacio={rewards.length === 0 ? 'Todavía no hay premios publicados.' : null}
                    columnas={colsRewards} filas={rewards.map((r) => ({ ...r, withdrawn: r.withdrawn ? 'sí' : 'no' }))}
                    nombreCsv="stock-por-premio.csv"
                >
                    <div className="chart-box">
                        <Bar
                            options={opcionesBar({ apilado: true })}
                            data={{
                                labels: rewards.map((r) => r.name),
                                datasets: [
                                    { label: 'Entregados', data: rewards.map((r) => r.handedOver), backgroundColor: COLOR.emerald },
                                    { label: 'Restantes', data: rewards.map((r) => r.remaining), backgroundColor: COLOR.rose },
                                ],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Entregas por hora" icono={<Clock size={15} />}
                    vacio={entregasHora.length === 0 ? 'Todavía no se entregó ningún premio.' : null}
                    columnas={[
                        { key: 'bucket', label: 'Hora' },
                        { key: 'count', label: 'Entregas' },
                    ]}
                    filas={entregasHora} nombreCsv="entregas-por-hora.csv"
                >
                    <div className="chart-box chart-box-sm">
                        <Bar
                            options={opcionesBar()}
                            data={{
                                labels: entregasHora.map((p) => etiquetaHora(p.bucket)),
                                datasets: [{ label: 'Entregas', data: entregasHora.map((p) => p.count), backgroundColor: COLOR.cyan }],
                            }}
                        />
                    </div>
                </Panel>
            </div>

            <div className="section-title"><Users size={16} /> Participantes</div>
            <div className="stat-panel-grid">
                <Panel
                    titulo="Distribución de saldos" icono={<BarChart3 size={15} />}
                    vacio={null}
                    columnas={[
                        { key: 'band', label: 'Puntos' },
                        { key: 'count', label: 'Participantes' },
                    ]}
                    filas={bands} nombreCsv="distribucion-saldos.csv"
                >
                    <div className="chart-box chart-box-sm">
                        <Bar
                            options={opcionesBar()}
                            data={{
                                labels: bands.map((b) => b.band),
                                datasets: [{ label: 'Participantes', data: bands.map((b) => b.count), backgroundColor: COLOR.purple }],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Stands visitados por participante" icono={<MapPin size={15} />}
                    vacio={null}
                    columnas={[
                        { key: 'standsVisited', label: 'Stands visitados' },
                        { key: 'count', label: 'Participantes' },
                    ]}
                    filas={visitados} nombreCsv="stands-visitados.csv"
                >
                    <div className="chart-box chart-box-sm">
                        <Bar
                            options={opcionesBar()}
                            data={{
                                labels: visitados.map((v) => v.standsVisited),
                                datasets: [{ label: 'Participantes', data: visitados.map((v) => v.count), backgroundColor: COLOR.emerald }],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Más puntos" icono={<Users size={15} />}
                    vacio={top.length === 0 ? 'Todavía no hay participantes.' : null}
                    columnas={[
                        { key: 'name', label: 'Nombre' },
                        { key: 'points', label: 'Puntos' },
                        { key: 'removed', label: 'Retirado' },
                        { key: 'barred', label: 'Sin canje' },
                    ]}
                    filas={top.map((p) => ({ ...p, removed: p.removed ? 'sí' : 'no', barred: p.barred ? 'sí' : 'no' }))}
                    nombreCsv="top-participantes.csv"
                >
                    <Tabla
                        columnas={[
                            { key: 'name', label: 'Nombre' },
                            { key: 'points', label: 'Puntos' },
                            { key: 'removed', label: 'Retirado' },
                            { key: 'barred', label: 'Sin canje' },
                        ]}
                        filas={top.map((p) => ({ ...p, removed: p.removed ? 'sí' : 'no', barred: p.barred ? 'sí' : 'no' }))}
                        vacio="Todavía no hay participantes."
                    />
                </Panel>
            </div>

            <div className="section-title"><ShieldAlert size={16} /> Operación</div>
            <div className="stat-panel-grid">
                <Panel
                    titulo="Códigos de canje" icono={<Gift size={15} />}
                    vacio={null}
                    columnas={[
                        { key: 'estado', label: 'Estado' },
                        { key: 'total', label: 'Códigos' },
                    ]}
                    filas={[
                        { estado: 'Emitidos', total: codigos.issued },
                        { estado: 'Usados', total: codigos.used },
                        { estado: 'Reemplazados', total: codigos.replaced },
                        { estado: 'Vencidos', total: codigos.expired },
                    ]}
                    nombreCsv="codigos-de-canje.csv"
                >
                    <div className="chart-box chart-box-sm">
                        <Doughnut
                            options={{ responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } } }}
                            data={{
                                labels: ['Usados', 'Reemplazados', 'Vencidos'],
                                datasets: [{
                                    data: [codigos.used, codigos.replaced, codigos.expired],
                                    backgroundColor: [COLOR.emerald, COLOR.amber, COLOR.rose],
                                }],
                            }}
                        />
                    </div>
                </Panel>

                <Panel
                    titulo="Ajustes manuales por motivo" icono={<Wand2 size={15} />}
                    vacio={ajustes.byReason.length === 0 ? 'Sin ajustes manuales en este rango.' : null}
                    columnas={[
                        { key: 'reason', label: 'Motivo' },
                        { key: 'amount', label: 'Puntos' },
                        { key: 'count', label: 'Ajustes' },
                    ]}
                    filas={ajustes.byReason} nombreCsv="ajustes-manuales.csv"
                >
                    <Tabla
                        columnas={[
                            { key: 'reason', label: 'Motivo' },
                            { key: 'amount', label: 'Puntos' },
                            { key: 'count', label: 'Ajustes' },
                        ]}
                        filas={ajustes.byReason}
                        vacio="Sin ajustes manuales en este rango."
                    />
                </Panel>

                <Panel
                    titulo="Acciones rechazadas por motivo" icono={<ShieldAlert size={15} />}
                    vacio={refusals.length === 0 ? 'Sin rechazos en este rango.' : null}
                    columnas={[
                        { key: 'action', label: 'Acción' },
                        { key: 'reason', label: 'Motivo' },
                        { key: 'count', label: 'Veces' },
                    ]}
                    filas={refusals} nombreCsv="rechazos.csv"
                >
                    <Tabla
                        columnas={[
                            { key: 'action', label: 'Acción' },
                            { key: 'reason', label: 'Motivo' },
                            { key: 'count', label: 'Veces' },
                        ]}
                        filas={refusals}
                        vacio="Sin rechazos en este rango."
                    />
                </Panel>

                <Panel
                    titulo="Premios nunca entregados" icono={<Gift size={15} />}
                    vacio="Todos los premios registraron alguna entrega."
                    columnas={[
                        { key: 'name', label: 'Premio' },
                        { key: 'stand', label: 'Stand' },
                        { key: 'cost', label: 'Costo' },
                        { key: 'remaining', label: 'Stock restante' },
                    ]}
                    filas={sinEntregar} nombreCsv="premios-nunca-entregados.csv"
                >
                    <Tabla
                        columnas={[
                            { key: 'name', label: 'Premio' },
                            { key: 'stand', label: 'Stand' },
                            { key: 'cost', label: 'Costo' },
                            { key: 'remaining', label: 'Stock restante' },
                        ]}
                        filas={sinEntregar}
                        vacio="Todos los premios registraron alguna entrega."
                    />
                </Panel>
            </div>
        </div>
    );
}
