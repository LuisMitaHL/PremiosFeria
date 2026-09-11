/* ============================================
   Preferencias del dispositivo
   ============================================

   Lo que este telefono ya vio: los avisos de actividad que se le mostraron
   (spec 029, R6) y los recorridos guiados que ya corrio (spec 030, R3).

   Nada de esto va a la base. Que un telefono haya visto un aviso es un hecho
   sobre el telefono, no sobre la feria: dos personas que se prestan un
   dispositivo comparten la respuesta, y esta bien que asi sea.

   Todo lector y todo escritor va envuelto en try/catch. localStorage lanza en
   una ventana privada o con el almacenamiento bloqueado, y ninguna de las dos
   funcionalidades puede romperse por eso: en el peor caso un aviso se repite o
   un recorrido vuelve a correr (spec 029 R20, spec 030 edge cases).
   ============================================ */

const AVISOS_KEY = 'cq_avisos_vistos';
const TOUR_KEY = 'cq_tours_vistos';

// El tope existe para que la lista no crezca sin limite en un dispositivo que
// se usa toda la feria. Treinta actividades es mas de lo que un evento de diez
// stands puede tener, asi que en la practica nunca se recorta.
const MAX_AVISOS = 60;

function leerLista(clave) {
    try {
        const crudo = localStorage.getItem(clave);
        const lista = crudo ? JSON.parse(crudo) : [];
        return Array.isArray(lista) ? lista : [];
    } catch {
        return [];
    }
}

function guardarLista(clave, lista) {
    try {
        localStorage.setItem(clave, JSON.stringify(lista));
    } catch {
        // Sin almacenamiento el aviso se repetira. Es el modo de fallo que la
        // spec acepta a proposito: peor seria no avisar.
    }
}

export function avisoYaVisto(actividadId) {
    return leerLista(AVISOS_KEY).includes(actividadId);
}

export function marcarAvisoVisto(actividadId) {
    const lista = leerLista(AVISOS_KEY);
    if (lista.includes(actividadId)) return;
    lista.push(actividadId);
    guardarLista(AVISOS_KEY, lista.slice(-MAX_AVISOS));
}

export function tourYaVisto(nombre) {
    return leerLista(TOUR_KEY).includes(nombre);
}

export function marcarTourVisto(nombre) {
    const lista = leerLista(TOUR_KEY);
    if (lista.includes(nombre)) return;
    lista.push(nombre);
    guardarLista(TOUR_KEY, lista);
}
