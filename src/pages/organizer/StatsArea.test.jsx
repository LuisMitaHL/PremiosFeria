import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

// Chart.js dibuja en canvas, que jsdom no tiene. Lo que se prueba aca no es el
// grafico en si -- eso es la libreria -- sino el contrato de la pantalla: que
// cada figura tenga un estado vacio, que se vea cuando se leyo, y que un
// rechazo del servidor se muestre tal cual.
vi.mock('chart.js', () => ({
    Chart: { register: vi.fn() },
    CategoryScale: {}, LinearScale: {}, BarElement: {}, PointElement: {},
    LineElement: {}, ArcElement: {}, Tooltip: {}, Legend: {},
}));
vi.mock('react-chartjs-2', () => ({
    Bar: () => <div data-testid="chart" />,
    Line: () => <div data-testid="chart" />,
    Doughnut: () => <div data-testid="chart" />,
}));
vi.mock('../../lib/api.js', () => ({
    getEventStatistics: vi.fn(),
    onReturnToScreen: vi.fn(() => () => {}),
}));

import StatsArea from './StatsArea';
import { getEventStatistics } from '../../lib/api.js';

const lleno = {
    generatedAt: '2026-09-11T22:00:00Z',
    from: null,
    to: null,
    timezone: 'America/La_Paz',
    callouts: {
        busiestHour: { bucket: '2026-09-11T11:00', scans: 3 },
        topStandByPoints: { stand: 'Stand Uno', points: 190 },
        mostHandedOverReward: { reward: 'Gorra', count: 2 },
        registeredWithoutScan: 1,
        standsWithoutScans: [{ stand: 'Stand Tres', standNumber: '3' }],
    },
    attendance: {
        timeline: [{
            bucket: '2026-09-11T11:00', visits: 3, activities: 1,
            activeParticipants: 2, registrations: 1,
            pointsAwarded: 130, pointsSpent: 0, cumulativePointsAwarded: 130,
        }],
        bounds: { firstScan: '2026-09-11T14:10:00Z', lastScan: '2026-09-11T15:20:00Z', durationMinutes: 70 },
    },
    stands: [{
        id: 's1', name: 'Stand Uno', standNumber: '1', withdrawn: false,
        visits: 3, activities: 1, visitPoints: 90, activityPoints: 100,
        totalPoints: 190, totalScans: 4, avgPoints: 47.5,
    }],
    adjustments: { total: 30, count: 2, byReason: [{ reason: 'compensa', amount: 40, count: 1 }] },
    rewards: [{
        id: 'r1', name: 'Gorra', stand: 'Stand Uno', cost: 200,
        withdrawn: false, handedOver: 2, pointsSpent: 400, remaining: 1,
    }],
    handoversPerHour: [{ bucket: '2026-09-11T16:00', count: 2 }],
    participants: {
        balanceBands: [{ band: '0', count: 1 }, { band: '300+', count: 1 }],
        standsVisited: [{ standsVisited: 0, count: 1 }, { standsVisited: 2, count: 1 }],
        registeredWithoutScan: 1,
        top: [{ name: 'Caro', points: 300, removed: true, barred: false }],
    },
    operations: {
        refusals: [{ action: 'scan.award', reason: 'cooldown', count: 2 }],
        claimCodes: { issued: 3, used: 1, replaced: 1, expired: 1 },
    },
};

const vacio = {
    ...lleno,
    callouts: {
        busiestHour: null, topStandByPoints: null, mostHandedOverReward: null,
        registeredWithoutScan: 0, standsWithoutScans: [],
    },
    attendance: { timeline: [], bounds: { firstScan: null, lastScan: null, durationMinutes: 0 } },
    stands: [],
    adjustments: { total: 0, count: 0, byReason: [] },
    rewards: [],
    handoversPerHour: [],
    participants: { balanceBands: [], standsVisited: [], registeredWithoutScan: 0, top: [] },
    operations: { refusals: [], claimCodes: { issued: 0, used: 0, replaced: 0, expired: 0 } },
};

describe('StatsArea', () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it('shows a snapshot timestamp and the call-outs when there is data', async () => {
        getEventStatistics.mockResolvedValue(lleno);

        render(<StatsArea />);

        expect(await screen.findByText(/Leído a las/)).toBeInTheDocument();
        expect(screen.getByText('Hora más ocupada')).toBeInTheDocument();
        expect(screen.getByText('190')).toBeInTheDocument();
        expect(screen.getByText('Gorra')).toBeInTheDocument();
    });

    it('states the absence instead of erroring when the window is empty', async () => {
        getEventStatistics.mockResolvedValue(vacio);

        render(<StatsArea />);

        expect(await screen.findByText('Sin escaneos en este rango.')).toBeInTheDocument();
        // Tres paneles de premios comparten el mismo vacío, y así debe ser.
        expect(screen.getAllByText('Todavía no hay premios publicados.').length).toBeGreaterThan(0);
        expect(screen.getByText('Sin rechazos en este rango.')).toBeInTheDocument();
        // La exportacion sigue disponible aunque no haya nada que exportar (R45).
        expect(screen.getAllByText('CSV').length).toBeGreaterThan(0);
    });

    it('shows the server refusal instead of a screen of zeros', async () => {
        getEventStatistics.mockResolvedValue({ error: 'No autorizado' });

        render(<StatsArea />);

        expect(await screen.findByText('No autorizado')).toBeInTheDocument();
    });
});
