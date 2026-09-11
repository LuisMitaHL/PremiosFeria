import { useState, useEffect, useCallback } from 'react';
import { Loader, AlertTriangle, Ban, RotateCcw, Coins, Boxes } from 'lucide-react';
import {
    getRewards,
    organizerSetRewardCost,
    organizerSetRewardStock,
    organizerSetRewardWithdrawn,
} from '../../lib/api.js';
import DynamicIcon from '../../components/DynamicIcon.jsx';

// El organizador corrige, no publica: registrar un premio sigue siendo del
// stand que lo trae (spec 023, R27). Lo que hay aca son las tres correcciones
// que alguien pide a gritos en media feria -- un precio mal puesto, un stock
// que no coincide con la mesa, un premio que ya no esta -- y ninguna de ellas
// borra nada (R23).
export default function RewardsArea() {
    const [premios, setPremios] = useState([]);
    const [cargando, setCargando] = useState(true);
    const [error, setError] = useState('');
    const [edicion, setEdicion] = useState({});

    const cargar = useCallback(async () => {
        try {
            const filas = await getRewards();
            setPremios(
                filas.sort((a, b) =>
                    (a.communities?.name || '').localeCompare(b.communities?.name || '') ||
                    a.name.localeCompare(b.name)
                )
            );
        } catch (err) {
            setError(err.message);
        } finally {
            setCargando(false);
        }
    }, []);

    useEffect(() => {
        cargar();
    }, [cargar]);

    async function aplicar(fn) {
        setError('');
        try {
            const res = await fn();
            if (res?.error) {
                setError(res.error);
                return false;
            }
            await cargar();
            return true;
        } catch (err) {
            setError(err.message);
            return false;
        }
    }

    function campo(id, clave, valorPorDefecto) {
        return edicion[id]?.[clave] ?? String(valorPorDefecto);
    }

    function editar(id, clave, valor) {
        setEdicion((e) => ({ ...e, [id]: { ...e[id], [clave]: valor } }));
    }

    if (cargando) {
        return (
            <div className="empty-state">
                <Loader size={28} className="spin-icon" />
            </div>
        );
    }

    return (
        <div>
            <p className="empty-hint" style={{ marginBottom: 16 }}>
                Corrige el precio, el stock o retira un premio de cualquier stand. Para publicar uno
                nuevo, lo hace el stand que lo trae.
            </p>

            {error && (
                <p className="form-error">
                    <AlertTriangle size={14} /> {error}
                </p>
            )}

            {premios.length === 0 && (
                <div className="empty-state">
                    <p>Todavía no hay premios publicados.</p>
                    <p className="empty-hint">Cada stand registra los suyos desde su consola.</p>
                </div>
            )}

            {premios.map((p) => (
                <div
                    key={p.id}
                    className={`glass-card activity-card ${p.is_withdrawn ? 'is-finished' : ''}`}
                >
                    <div className="activity-head">
                        <div className="activity-name">
                            <DynamicIcon name={p.emoji} size={20} />
                            {p.name}
                        </div>
                        {p.is_withdrawn ? (
                            <span className="badge badge-finished">Retirado</span>
                        ) : (
                            <span className="badge badge-scheduled">{p.cost} pts</span>
                        )}
                    </div>

                    <div className="activity-meta">
                        {p.communities?.name || 'Sin stand'} · {p.stock} en existencia
                    </div>

                    <div className="activity-actions">
                        <input
                            className="form-input"
                            type="number"
                            style={{ maxWidth: 100 }}
                            value={campo(p.id, 'cost', p.cost)}
                            onChange={(e) => editar(p.id, 'cost', e.target.value)}
                        />
                        <button
                            className="btn btn-ghost"
                            onClick={() =>
                                aplicar(() =>
                                    organizerSetRewardCost(p.id, Number(campo(p.id, 'cost', p.cost)))
                                )
                            }
                        >
                            <Coins size={14} /> Precio
                        </button>

                        <input
                            className="form-input"
                            type="number"
                            style={{ maxWidth: 100 }}
                            value={campo(p.id, 'stock', p.stock)}
                            onChange={(e) => editar(p.id, 'stock', e.target.value)}
                        />
                        <button
                            className="btn btn-ghost"
                            onClick={() =>
                                aplicar(() =>
                                    organizerSetRewardStock(
                                        p.id,
                                        Number(campo(p.id, 'stock', p.stock))
                                    )
                                )
                            }
                        >
                            <Boxes size={14} /> Stock
                        </button>

                        <button
                            className="btn btn-ghost"
                            onClick={() => aplicar(() => organizerSetRewardWithdrawn(p.id, !p.is_withdrawn))}
                        >
                            {p.is_withdrawn ? (
                                <>
                                    <RotateCcw size={14} /> Reincorporar
                                </>
                            ) : (
                                <>
                                    <Ban size={14} /> Retirar
                                </>
                            )}
                        </button>
                    </div>
                </div>
            ))}
        </div>
    );
}
