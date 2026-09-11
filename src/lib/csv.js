/* ============================================
   csv.js — exportar una figura como CSV (spec 031)

   Sin dependencias a proposito: el navegador ya sabe descargar un archivo. Una
   libreria de documentos o de compresion seria peso anadido para lo unico que
   hace falta -- que el organizador se quede con los numeros despues de desarmar
   la feria (spec 031, R46).
   ============================================ */

// Comilla un campo segun RFC 4180: comillas dobles, comas y saltos de linea
// obligan a encerrar el valor entre comillas y a duplicar las de adentro.
function campo(valor) {
    const s = valor === null || valor === undefined ? '' : String(valor);
    return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

// columns: [{ key, label }]. rows: objetos con esas claves. Sin filas devuelve
// solo el encabezado, que es lo que R45 pide para una figura vacia.
export function toCsv(columns, rows) {
    const encabezado = columns.map((c) => campo(c.label)).join(',');
    const cuerpo = rows.map((fila) => columns.map((c) => campo(fila[c.key])).join(','));
    return [encabezado, ...cuerpo].join('\n');
}

export function downloadCsv(nombre, csv) {
    // El BOM delante hace que Excel abra bien los acentos; sin el, "compensación"
    // sale como "compensaciÃ³n" en la herramienta que el organizador usa.
    const blob = new Blob(['\ufeff', csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    enlace.href = url;
    enlace.download = nombre;
    document.body.appendChild(enlace);
    enlace.click();
    document.body.removeChild(enlace);
    URL.revokeObjectURL(url);
}
