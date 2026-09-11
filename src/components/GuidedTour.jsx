import { useState, useEffect, useCallback } from 'react';
import { X } from 'lucide-react';
import { tourYaVisto, marcarTourVisto } from '../lib/devicePrefs.js';
import { abrirCapa, cerrarCapa } from '../lib/overlay.js';

// Un recorrido guiado escrito a mano y no una libreria.
//
// Son dos pantallas y nueve pasos, contra una dependencia que habria que
// cargar siempre para usarla un minuto en la primera visita, y que ademas
// tendria que respetar el piso de Chromium 83 (ADR 0005). Nada de lo que hay
// aca es posterior a eso: getBoundingClientRect, scrollIntoView con opciones y
// un box-shadow enorme para oscurecer todo menos el elemento senalado.
//
// El recorrido NO actua: no navega, no pulsa nada, no envia formularios (spec
// 030, R12). En la consola del stand eso no es una preferencia de estilo --
// los elementos que senala inician actividades y confirman entregas.

// Margen entre el elemento senalado y el recuadro que lo explica.
const SEPARACION = 12;

export default function GuidedTour({ nombre, pasos, onTerminar }) {
    const [indice, setIndice] = useState(0);
    const [rect, setRect] = useState(null);
    const [activo, setActivo] = useState(() => !tourYaVisto(nombre));

    // Se anuncia en cuanto se sabe que el recorrido va a correr, no cuando
    // pinta: entre una cosa y la otra hay una medicion, y en esa ventana un
    // aviso de actividad alcanzaba a mostrarse para quedar tapado.
    useEffect(() => {
        if (!activo) return;
        abrirCapa();
        return cerrarCapa;
    }, [activo]);

    const terminar = useCallback(() => {
        marcarTourVisto(nombre);
        setActivo(false);
        if (onTerminar) onTerminar();
    }, [nombre, onTerminar]);

    // Busca el elemento del paso actual. Si no esta, se salta al siguiente en
    // vez de senalar el vacio: una pantalla puede no tener una seccion todavia.
    useEffect(() => {
        if (!activo) return;
        if (indice >= pasos.length) {
            terminar();
            return;
        }

        const el = document.querySelector(pasos[indice].selector);
        if (!el) {
            setIndice((i) => i + 1);
            return;
        }

        el.scrollIntoView({ block: 'center', inline: 'nearest' });

        const medir = () => setRect(el.getBoundingClientRect());
        // Una vuelta del navegador para que el desplazamiento termine antes de
        // medir; si no, el recuadro aparece donde el elemento estaba.
        const t = setTimeout(medir, 260);
        window.addEventListener('resize', medir);
        window.addEventListener('orientationchange', medir);
        return () => {
            clearTimeout(t);
            window.removeEventListener('resize', medir);
            window.removeEventListener('orientationchange', medir);
        };
    }, [activo, indice, pasos, terminar]);

    if (!activo || indice >= pasos.length || !rect) return null;

    const paso = pasos[indice];
    const esUltimo = indice === pasos.length - 1;

    // Arriba o abajo segun donde este el elemento, para no taparlo nunca (R23).
    const centroY = rect.top + rect.height / 2;
    const debajo = centroY < window.innerHeight / 2;
    const estiloCuadro = debajo
        ? { top: rect.bottom + SEPARACION }
        : { bottom: window.innerHeight - rect.top + SEPARACION };

    return (
        <div className="tour-capa">
            <div
                className="tour-foco"
                style={{
                    top: rect.top - 6,
                    left: rect.left - 6,
                    width: rect.width + 12,
                    height: rect.height + 12,
                }}
            />

            <div className="tour-cuadro" style={estiloCuadro}>
                <button
                    type="button"
                    className="tour-salir"
                    aria-label="Saltar el recorrido"
                    onClick={terminar}
                >
                    <X size={16} />
                </button>

                <h3 className="tour-titulo">{paso.titulo}</h3>
                <p className="tour-texto">{paso.texto}</p>

                <div className="tour-pie">
                    <span className="tour-progreso">
                        {indice + 1} de {pasos.length}
                    </span>
                    <button
                        type="button"
                        className="btn btn-primary tour-siguiente"
                        onClick={() => (esUltimo ? terminar() : setIndice((i) => i + 1))}
                    >
                        {esUltimo ? 'Entendido' : 'Siguiente'}
                    </button>
                </div>
            </div>
        </div>
    );
}
