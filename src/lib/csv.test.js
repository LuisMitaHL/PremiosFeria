import { describe, it, expect } from 'vitest';
import { toCsv } from './csv';

// La exportacion no puede deformar los datos que muestra: una coma en un motivo
// de ajuste o unas comillas en el nombre de un premio son parte del valor.
describe('toCsv', () => {
    const columnas = [
        { key: 'nombre', label: 'Nombre' },
        { key: 'puntos', label: 'Puntos' },
    ];

    it('writes a header only when there are no rows', () => {
        expect(toCsv(columnas, [])).toBe('Nombre,Puntos');
    });

    it('writes one line per row in the requested column order', () => {
        const csv = toCsv(columnas, [
            { nombre: 'Ana', puntos: 120 },
            { nombre: 'Beto', puntos: 0 },
        ]);
        expect(csv).toBe('Nombre,Puntos\nAna,120\nBeto,0');
    });

    it('quotes values containing commas, quotes or newlines', () => {
        const csv = toCsv(columnas, [{ nombre: 'Ana, la del stand', puntos: 1 }]);
        expect(csv).toBe('Nombre,Puntos\n"Ana, la del stand",1');

        const conComillas = toCsv([{ key: 'r', label: 'R' }], [{ r: 'dijo "hola"' }]);
        expect(conComillas).toBe('R\n"dijo ""hola"""');

        const conSalto = toCsv([{ key: 'r', label: 'R' }], [{ r: 'una\ndos' }]);
        expect(conSalto).toBe('R\n"una\ndos"');
    });

    it('renders null and undefined as empty fields', () => {
        expect(toCsv(columnas, [{ nombre: null, puntos: undefined }])).toBe('Nombre,Puntos\n,');
    });
});
