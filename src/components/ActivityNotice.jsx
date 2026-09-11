import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Zap, Star, X } from 'lucide-react';
import { getAllActivities, getScansForParticipant, startPolling } from '../lib/api.js';
import { avisoYaVisto, marcarAvisoVisto } from '../lib/devicePrefs.js';
import { hayCapa } from '../lib/overlay.js';

// Cuanto queda un aviso en pantalla antes de irse solo. Suficiente para leer
// dos renglones sin apuro, corto para no quedarse encima de lo que el
// estudiante estaba haciendo (spec 029, R12).
const EN_PANTALLA_MS = 9000;

// Esto NO es un sistema de notificaciones, y la spec 029 es deliberada al
// respecto: no hay permiso que pedir, ni service worker que entregue nada, ni
// suscripcion que registrar. Nada llega a una aplicacion cerrada.
//
// Lo que hay es una comparacion: el cliente ya relee las actividades cada pocos
// segundos (spec 028), y una actividad que esta en curso y que este telefono
// todavia no vio es un aviso. El ciclo de vida de una actividad se deriva
// (spec 019) y nada corre en segundo plano (ADR 0003), asi que "empezo" solo
// puede significar eso.
export default function ActivityNotice({ participantId }) {
    const navigate = useNavigate();
    const [cola, setCola] = useState([]);
    const [actual, setActual] = useState(null);
    // Solo para volver a intentar mostrar un aviso que tuvo que esperar.
    const [reintento, setReintento] = useState(0);

    // Lo que ya esta en la cola o en pantalla, para no encolarlo dos veces
    // entre una lectura y la siguiente.
    const encoladas = useRef(new Set());

    const buscar = useCallback(async () => {
        if (!participantId) return;
        try {
            const [actividades, scans] = await Promise.all([
                getAllActivities(),
                getScansForParticipant(participantId),
            ]);

            // Lo que este estudiante ya hizo. Mandarlo a hacer de nuevo algo que
            // ya hizo es la forma mas rapida de que deje de leer los avisos
            // (spec 029, R5).
            const completadas = new Set(
                scans.filter((s) => s.type === 'activity' && s.activity_id).map((s) => s.activity_id)
            );

            const nuevas = actividades.filter(
                (a) =>
                    a.activity_state === 'running' &&
                    !a.communities?.is_withdrawn &&
                    !completadas.has(a.id) &&
                    !encoladas.current.has(a.id) &&
                    !avisoYaVisto(a.id)
            );
            if (nuevas.length === 0) return;

            nuevas.forEach((a) => encoladas.current.add(a.id));
            setCola((previa) => [...previa, ...nuevas]);
        } catch {
            // Una lectura fallida no produce aviso; la siguiente que funcione lo
            // producira. No hay nada que decirle al estudiante sobre esto.
        }
    }, [participantId]);

    useEffect(() => {
        if (!participantId) return;
        buscar();
        return startPolling(buscar);
    }, [participantId, buscar]);

    // De a uno. Dos avisos a la vez son un dialogo, y al segundo no lo lee
    // nadie (spec 029, R7).
    useEffect(() => {
        if (actual || cola.length === 0) return;

        // Mientras el recorrido guiado esta en pantalla, un aviso saldria
        // detras de su capa oscura: ilegible, y dado por visto igual, con lo
        // que el estudiante lo pierde para siempre. Espera a que termine.
        if (hayCapa()) {
            const t = setTimeout(() => setReintento((n) => n + 1), 1000);
            return () => clearTimeout(t);
        }

        const siguiente = cola[0];
        setCola((previa) => previa.slice(1));
        setActual(siguiente);
        // Se marca visto al mostrarlo, no al cerrarlo: si el estudiante cierra
        // la aplicacion con el aviso en pantalla, ya lo vio.
        marcarAvisoVisto(siguiente.id);
    }, [actual, cola, reintento]);

    useEffect(() => {
        if (!actual) return;
        const t = setTimeout(() => setActual(null), EN_PANTALLA_MS);
        return () => clearTimeout(t);
    }, [actual]);

    if (!actual) return null;

    const stand = actual.communities?.name || 'Un stand';

    return (
        <div className="activity-notice" role="status">
            <button
                type="button"
                className="activity-notice-body"
                onClick={() => {
                    setActual(null);
                    navigate('/activities');
                }}
            >
                <span className="activity-notice-icon">
                    {actual.is_main_event ? <Star size={18} /> : <Zap size={18} />}
                </span>
                <span className="activity-notice-text">
                    <strong>{actual.name}</strong>
                    <span className="activity-notice-meta">
                        {stand} · empezó ahora
                        {actual.is_main_event ? ' · evento principal' : ''}
                    </span>
                </span>
            </button>
            <button
                type="button"
                className="activity-notice-close"
                aria-label="Cerrar aviso"
                onClick={() => setActual(null)}
            >
                <X size={16} />
            </button>
        </div>
    );
}
