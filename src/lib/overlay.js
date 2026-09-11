/* ============================================
   Hay algo cubriendo la pantalla
   ============================================

   Un contador, no un booleano, para que dos capas superpuestas no se pisen al
   cerrarse: la segunda en cerrar es la que libera.

   Existe porque preguntarselo al DOM no sirve. El recorrido guiado tarda unos
   cientos de milisegundos en medir su primer elemento antes de pintar nada, y
   en esa ventana un aviso de actividad se mostraba, se daba por visto y quedaba
   detras de la capa oscura en cuanto esta aparecia: ilegible y perdido para
   siempre, porque un aviso se muestra una sola vez por dispositivo.
   ============================================ */

let capas = 0;

export function abrirCapa() {
    capas += 1;
}

export function cerrarCapa() {
    capas = Math.max(0, capas - 1);
}

export function hayCapa() {
    return capas > 0;
}
