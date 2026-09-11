import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/authContext.js';
import { scanQR } from '../lib/api.js';
import { decodeQRPayload } from '../lib/qrSecurity.js';
import { ScanLine, Loader, PartyPopper, Frown, Clock, Home, CheckCircle, Lock, Camera, Keyboard } from 'lucide-react';
import DynamicIcon from '../components/DynamicIcon.jsx';

// Refusals that are the attendee's situation rather than a mistake. They are
// told what happened, not that something went wrong (spec 020, R13).
const EXPECTED_REFUSALS = [
    'Ya visitaste este stand',
    'Ya participaste en esta actividad',
    'Esta actividad ya terminó',
    'Esta actividad todavía no ha iniciado',
];

function isExpectedRefusal(reason) {
    return EXPECTED_REFUSALS.some((phrase) => (reason || '').startsWith(phrase));
}

export default function Scanner() {
    const navigate = useNavigate();
    const { participant, refreshParticipant } = useAuth();
    const [scanResult, setScanResult] = useState(null);
    const [scanning, setScanning] = useState(true);
    const [manualInput, setManualInput] = useState('');
    const [showManual, setShowManual] = useState(false);
    const [processing, setProcessing] = useState(false);
    const scannerRef = useRef(null);
    const html5QrRef = useRef(null);

    // La camara se monta una vez y vive mientras dure el escaneo, pero
    // handleScan cambia en cada render porque cierra sobre participant y
    // processing. Pasarla como dependencia reiniciaria la camara a cada rato;
    // omitirla dejaba al callback con la version del primer render, que es la
    // que todavia no tenia participante: el primer escaneo de una pantalla
    // recien abierta contestaba "registrate para participar" con la sesion ya
    // cargada. La referencia mantiene una sola camara y siempre la funcion de
    // ahora.
    const handleScanRef = useRef(null);

    useEffect(() => {
        if (!participant) { navigate('/', { replace: true }); return; }
    }, [participant, navigate]);

    // Initialize camera scanner
    useEffect(() => {
        if (!scanning || showManual) return;

        let scanner = null;

        const initScanner = async () => {
            try {
                const { Html5Qrcode } = await import('html5-qrcode');
                scanner = new Html5Qrcode('qr-reader');
                html5QrRef.current = scanner;

                await scanner.start(
                    { facingMode: 'environment' },
                    {
                        fps: 10,
                        qrbox: { width: 250, height: 250 },
                        aspectRatio: 1.0,
                    },
                    (decodedText) => {
                        handleScanRef.current(decodedText);
                        if (scanner && scanner.isScanning) {
                            scanner.stop().catch(() => { });
                        }
                    },
                    () => { } // ignore errors on each frame
                );
            } catch (err) {
                console.error('Camera error:', err);
                setShowManual(true);
            }
        };

        initScanner();

        return () => {
            if (scanner && scanner.isScanning) {
                scanner.stop().catch(() => { });
            }
        };
    }, [scanning, showManual]);

    handleScanRef.current = handleScan;

    async function handleScan(data) {
        if (!participant || processing) return;
        setScanning(false);
        setProcessing(true);

        try {
            // Determine if it's a short manual code or a full QR payload
            let decoded;
            if (data.trim().length <= 8) {
                // Short code entry
                decoded = { short_code: data.trim().toUpperCase() };
            } else {
                // Decode the QR payload to get the JSON string
                decoded = decodeQRPayload(data);
            }

            if (!decoded) {
                setScanResult({
                    success: false,
                    message: 'Código QR no reconocido',
                    points: 0,
                    groupName: '',
                    groupEmoji: '❌',
                });
                setProcessing(false);
                return;
            }

            // Send decoded JSON to server for validation
            const jsonString = JSON.stringify(decoded);
            const result = await scanQR(jsonString);

            if (result.valid) {
                // Refresh participant to get updated points
                await refreshParticipant();
                setScanResult({
                    success: true,
                    message: '¡Puntos obtenidos!',
                    points: result.points,
                    groupName: result.groupName || result.groupname || '',
                    groupEmoji: result.groupEmoji || result.groupemoji || '📍',
                    type: result.type,
                });
            } else {
                setScanResult({
                    success: false,
                    expected: isExpectedRefusal(result.reason),
                    message: result.reason,
                    points: 0,
                    groupName: '',
                    groupEmoji: '',
                });
            }
        } catch (err) {
            setScanResult({
                success: false,
                message: err.message || 'Error al procesar el código QR',
                points: 0,
                groupName: '',
                groupEmoji: '❌',
            });
        } finally {
            setProcessing(false);
        }
    }

    function handleManualSubmit(e) {
        e.preventDefault();
        if (manualInput.trim()) {
            handleScan(manualInput.trim());
        }
    }

    function resetScanner() {
        setScanResult(null);
        setScanning(true);
        setManualInput('');
    }

    if (!participant) return null;

    // Show processing state
    if (processing) {
        return (
            <div className="page">
                <div className="container" style={{ paddingTop: 60, textAlign: 'center' }}>
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}><Loader size={40} className="spin-icon" /></div>
                    <h2>Validando código...</h2>
                    <p style={{ color: 'var(--text-secondary)' }}>Verificando con el servidor</p>
                </div>
            </div>
        );
    }

    // Show scan result
    if (scanResult) {
        return (
            <div className="page">
                <div className="container" style={{ paddingTop: 60 }}>
                    <div className={`scan-result ${scanResult.success ? 'success' : scanResult.expected ? 'neutral' : 'error'}`}>
                        <div className="result-icon">
                            {scanResult.success ? <PartyPopper size={48} /> : scanResult.expected ? <Clock size={48} /> : <Frown size={48} />}
                        </div>
                        <div className="result-title">
                            {scanResult.success ? '¡Éxito!' : scanResult.expected ? 'Nada que sumar' : 'Error'}
                        </div>

                        {scanResult.success && (
                            <>
                                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '2rem', marginBottom: 8, gap: 12 }}>
                                    <DynamicIcon name={scanResult.groupEmoji} size={32} />
                                    <span>{scanResult.groupName}</span>
                                </div>
                                <div className="result-points">+{scanResult.points} pts</div>
                                <div className="result-desc">
                                    {scanResult.type === 'visit' ? 'Visita al stand' : 'Actividad completada'}
                                </div>
                            </>
                        )}

                        {!scanResult.success && (
                            <div className="result-desc">{scanResult.message}</div>
                        )}

                        <div style={{ display: 'flex', gap: 12, justifyContent: 'center', marginTop: 24 }}>
                            <button className="btn btn-primary" onClick={resetScanner}>
                                <ScanLine size={16} /> Escanear otro
                            </button>
                            <button className="btn btn-outline" onClick={() => navigate('/dashboard')}>
                                <Home size={16} /> Dashboard
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    return (
        <div className="page">
            <div className="container">
                <div className="page-header" style={{ textAlign: 'center' }}>
                    <h1><ScanLine size={22} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 8 }} />Escanear QR</h1>
                    <p>Apunta la cámara al código QR del stand</p>
                </div>

                {!showManual && (
                    <div className="scanner-container">
                        <div id="qr-reader" ref={scannerRef} style={{ width: '100%' }}></div>
                        <div className="scanner-overlay">
                            <div className="scan-line"></div>
                        </div>
                    </div>
                )}

                <div style={{ textAlign: 'center', marginTop: 16 }}>
                    <button
                        className="btn btn-outline"
                        onClick={() => setShowManual(!showManual)}
                        style={{ fontSize: '0.85rem' }}
                    >
                        {showManual ? <><Camera size={14} /> Usar cámara</> : <><Keyboard size={14} /> Ingresar código manualmente</>}
                    </button>
                </div>

                {showManual && (
                    <form onSubmit={handleManualSubmit} style={{ marginTop: 24 }}>
                        <div className="glass-card">
                            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 16 }}>
                                Introduce el código manual de 6 caracteres o pega el código QR:
                            </p>
                            <div className="form-group">
                                <textarea
                                    className="form-input"
                                    rows={3}
                                    placeholder="Ej: A1B2C3"
                                    value={manualInput}
                                    onChange={e => setManualInput(e.target.value)}
                                    style={{ resize: 'none', fontFamily: 'monospace', fontSize: '1.2rem', textAlign: 'center', textTransform: 'uppercase' }}
                                />
                            </div>
                            <button type="submit" className="btn btn-primary btn-full">
                                <CheckCircle size={16} /> Validar código
                            </button>
                        </div>
                    </form>
                )}

                <div className="glass-card" style={{ marginTop: 24, textAlign: 'center' }}>
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                        <Lock size={14} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} /> Los códigos QR rotan cada 15 segundos para tu seguridad. Asegúrate de escanear el QR que se muestra actualmente en el stand.
                    </p>
                </div>
            </div>
        </div>
    );
}
