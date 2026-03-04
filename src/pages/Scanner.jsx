import React, { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/AuthContext.jsx';
import { scanQR } from '../lib/api.js';
import { decodeQRPayload } from '../lib/qrSecurity.js';

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
                        handleScan(decodedText);
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

    async function handleScan(data) {
        if (!participant || processing) return;
        setScanning(false);
        setProcessing(true);

        try {
            // Decode the QR payload to get the JSON string
            const decoded = decodeQRPayload(data);

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
            const result = await scanQR(participant.id, jsonString);

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
                    message: result.reason,
                    points: 0,
                    groupName: '',
                    groupEmoji: '❌',
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
                    <div style={{ fontSize: '3rem', marginBottom: 16 }}>⏳</div>
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
                    <div className={`scan-result ${scanResult.success ? 'success' : 'error'}`}>
                        <div className="result-icon">
                            {scanResult.success ? '🎉' : '😔'}
                        </div>
                        <div className="result-title">
                            {scanResult.success ? '¡Éxito!' : 'Error'}
                        </div>

                        {scanResult.success && (
                            <>
                                <div style={{ fontSize: '2rem', marginBottom: 8 }}>
                                    {scanResult.groupEmoji} {scanResult.groupName}
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
                                📸 Escanear otro
                            </button>
                            <button className="btn btn-outline" onClick={() => navigate('/dashboard')}>
                                🏠 Dashboard
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
                    <h1>📸 Escanear QR</h1>
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
                        {showManual ? '📸 Usar cámara' : '⌨️ Ingresar código manualmente'}
                    </button>
                </div>

                {showManual && (
                    <form onSubmit={handleManualSubmit} style={{ marginTop: 24 }}>
                        <div className="glass-card">
                            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 16 }}>
                                Pega aquí el código QR si no puedes usar la cámara:
                            </p>
                            <div className="form-group">
                                <textarea
                                    className="form-input"
                                    rows={3}
                                    placeholder="Pega el código aquí..."
                                    value={manualInput}
                                    onChange={e => setManualInput(e.target.value)}
                                    style={{ resize: 'none', fontFamily: 'monospace', fontSize: '0.8rem' }}
                                />
                            </div>
                            <button type="submit" className="btn btn-primary btn-full">
                                ✅ Validar código
                            </button>
                        </div>
                    </form>
                )}

                <div className="glass-card" style={{ marginTop: 24, textAlign: 'center' }}>
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                        🔒 Los códigos QR rotan cada 30 segundos para tu seguridad. Asegúrate de escanear el QR que se muestra actualmente en el stand.
                    </p>
                </div>
            </div>
        </div>
    );
}
