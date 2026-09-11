import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, useSearchParams } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '../../lib/authContext.js';
import { getMyCommunity, getSignedScanCode } from '../../lib/api.js';
import { encodeQRPayload, getTimeUntilRotation } from '../../lib/qrSecurity.js';
import { Loader, XCircle, MapPin, Target, RefreshCw, Lock } from 'lucide-react';
import DynamicIcon from '../../components/DynamicIcon.jsx';

export default function QRDisplay() {
    const { groupId } = useParams();
    // Which code to project. An activity's code is reached from that activity,
    // so it is never ambiguous which one is on screen (spec 011, R3).
    const [searchParams] = useSearchParams();
    const activityId = searchParams.get('activity');
    const navigate = useNavigate();
    const { adminUser, adminLoading } = useAuth();

    const [community, setCommunity] = useState(null);
    const [qrType, setQrType] = useState(activityId ? 'activity' : 'visit');
    const [signError, setSignError] = useState('');
    const [qrData, setQrData] = useState('');
    const [shortCode, setShortCode] = useState('');
    const [timeLeft, setTimeLeft] = useState(15);
    const [activityName, setActivityName] = useState('');
    const [pointsLabel, setPointsLabel] = useState(null);
    const [loading, setLoading] = useState(true);

    // Redirect if not authenticated
    useEffect(() => {
        if (!adminLoading && !adminUser) {
            navigate('/admin/login', { replace: true });
        }
    }, [adminUser, adminLoading, navigate]);

    // Load community
    useEffect(() => {
        if (!adminUser) return;

        // Si la pantalla se cierra o cambia de stand con la peticion en vuelo,
        // la respuesta que llegue tarde no debe escribir nada: dos lecturas que
        // se cruzan dejarian en pantalla la comunidad equivocada.
        let vigente = true;

        const load = async () => {
            try {
                const fila = await getMyCommunity(adminUser.id);
                if (vigente) setCommunity(fila);
            } catch (err) {
                console.error('QR load error:', err);
            } finally {
                if (vigente) setLoading(false);
            }
        };
        load();

        return () => {
            vigente = false;
        };
    }, [adminUser]);

    // El servidor firma el código; el secreto nunca llega al navegador
    const refreshQR = useCallback(async () => {
        if (!community) return;
        try {
            const result = await getSignedScanCode(
                community.id,
                qrType,
                qrType === 'activity' ? activityId : null
            );
            // The server refuses to sign an activity that is not running. Say so
            // and stop showing a code, rather than leaving the last one on
            // screen looking valid (spec 011, R11).
            if (result.error) {
                setSignError(result.error);
                setQrData('');
                setShortCode('');
                return;
            }
            setSignError('');
            setQrData(encodeQRPayload(result.payload));
            setShortCode(result.shortCode);
            setActivityName(result.payload?.activityName || '');
            setPointsLabel(result.points);
            setTimeLeft(getTimeUntilRotation());
        } catch {
            setSignError('No se pudo actualizar el código. Revisa la conexión.');
            setQrData('');
        }
    }, [community, qrType, activityId]);

    // Generate QR on mount and on type/community change
    useEffect(() => {
        refreshQR();
    }, [refreshQR]);

    // La cuenta atras, y la firma de un codigo nuevo cuando cambia la ventana.
    //
    // Antes esto llamaba a refreshQR() DENTRO del actualizador de setTimeLeft.
    // React puede ejecutar un actualizador mas de una vez, asi que una sola
    // rotacion podia pedir dos firmas, y la respuesta que llegara segunda
    // dejaba en pantalla un codigo de la ventana anterior.
    //
    // Ademas el contador ya no resta de a uno sino que se lee del reloj: un
    // intervalo acumula error, y el navegador lo estrangula si la pantalla del
    // stand queda en segundo plano. Un stand proyectando un codigo con la
    // cuenta atras equivocada es un stand que no da puntos.
    useEffect(() => {
        if (!community) return;

        let ventana = Math.floor(Date.now() / 15000);

        const interval = setInterval(() => {
            const ahora = Math.floor(Date.now() / 15000);
            setTimeLeft(getTimeUntilRotation());
            if (ahora !== ventana) {
                ventana = ahora;
                refreshQR();
            }
        }, 1000);

        return () => clearInterval(interval);
    }, [refreshQR, community]);

    if (loading || adminLoading) {
        return (
            <div className="page" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '80vh' }}>
                <div className="empty-state">
                    <div className="empty-icon"><Loader size={40} className="spin-icon" /></div>
                    <p>Cargando...</p>
                </div>
            </div>
        );
    }

    if (!community || community.id !== groupId) {
        return (
            <div className="page" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '80vh' }}>
                <div className="empty-state">
                    <div className="empty-icon"><XCircle size={40} /></div>
                    <p>No tienes acceso a esta comunidad</p>
                    <button className="btn btn-primary" onClick={() => navigate('/admin')} style={{ marginTop: 16 }}>
                        ← Volver al Admin
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <div className="container">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 0' }}>
                    <button className="btn btn-outline" onClick={() => navigate('/admin')} style={{ fontSize: '0.8rem' }}>
                        ← Admin
                    </button>
                    <div style={{ display: 'flex', gap: 8 }}>
                        <button
                            className={`btn ${qrType === 'visit' ? 'btn-primary' : 'btn-outline'}`}
                            onClick={() => setQrType('visit')}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            <MapPin size={14} /> Visita
                        </button>
                        <button
                            className={`btn ${qrType === 'activity' ? 'btn-primary' : 'btn-outline'}`}
                            onClick={() => setQrType('activity')}
                            style={{ fontSize: '0.8rem', padding: '8px 16px' }}
                        >
                            <Target size={14} /> Actividad
                        </button>
                    </div>
                </div>

                <div className="qr-display-fullscreen">
                    {/* Group Info */}
                    <div style={{ marginBottom: 24 }}>
                        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 8, color: 'var(--text-primary)' }}>
                            <DynamicIcon name={community.emoji} size={48} />
                        </div>
                        <h2 style={{ fontSize: '1.5rem', fontWeight: 800 }}>{community.name}</h2>
                        <p style={{ color: 'var(--text-secondary)' }}>
                            Stand {community.stand_number}
                            {pointsLabel !== null && ` · ${pointsLabel} pts`}
                            {qrType === 'activity' && activityName && ` · ${activityName}`}
                        </p>
                    </div>

                    {/* A refusal replaces the code. The dangerous failure is a
                        screen that keeps showing the last code it received,
                        because it looks exactly like a working one to everybody
                        in the room (spec 011). */}
                    {signError ? (
                        <div className="empty-state">
                            <p>{signError}</p>
                            <p className="empty-hint">
                                Este código ya no otorga puntos.
                            </p>
                        </div>
                    ) : (
                    <>
                    <div className="qr-wrapper" style={{ animation: timeLeft <= 5 ? 'pulse 0.5s ease-in-out infinite' : 'none' }}>
                        <QRCodeSVG
                            value={qrData || 'loading'}
                            size={260}
                            level="M"
                            includeMargin={false}
                            fgColor="#000000"
                            bgColor="#ffffff"
                        />
                    </div>

                    {/* Short Code for Manual Entry */}
                    <div className="glass-card" style={{ padding: '8px 24px', margin: '24px auto', display: 'inline-block', border: '1px solid var(--border-color)', borderRadius: '12px' }}>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '4px' }}>
                            Código Manual
                        </div>
                        <div style={{ fontSize: '2rem', fontWeight: 900, letterSpacing: '0.15em', color: 'var(--text-primary)', fontFamily: 'monospace' }}>
                            {shortCode}
                        </div>
                    </div>

                    {/* Timer */}
                    <div className="qr-timer" style={{ marginBottom: 16 }}>
                        <span><RefreshCw size={16} /></span>
                        <span style={{ color: timeLeft <= 5 ? 'var(--accent-rose)' : 'var(--text-primary)' }}>
                            {timeLeft}s
                        </span>
                        <div className="qr-timer-bar">
                            <div
                                className="qr-timer-fill"
                                style={{ width: `${(timeLeft / 15) * 100}%`, background: timeLeft <= 5 ? 'var(--gradient-warn)' : 'var(--gradient-primary)' }}
                            />
                        </div>
                    </div>

                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', maxWidth: 300, textAlign: 'center' }}>
                        <Lock size={14} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} /> El código QR se renueva cada 15 segundos para evitar uso indebido. Muestra esta pantalla a los visitantes.
                    </p>
                    </>
                    )}
                </div>
            </div>
        </div>
    );
}
