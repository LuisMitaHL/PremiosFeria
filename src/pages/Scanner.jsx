import React, { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { getParticipant, addPoints } from '../lib/storage.js';
import { validateQRPayload } from '../lib/qrSecurity.js';

export default function Scanner() {
    const navigate = useNavigate();
    const participant = getParticipant();
    const [scanResult, setScanResult] = useState(null); // { success, message, points, groupName, groupEmoji }
    const [scanning, setScanning] = useState(true);
    const [manualInput, setManualInput] = useState('');
    const [showManual, setShowManual] = useState(false);
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

    function handleScan(data) {
        if (!participant) return;
        setScanning(false);

        const result = validateQRPayload(data, participant.id);

        if (result.valid) {
            // Add points
            addPoints(participant.id, result.standId, result.points, result.type, result.groupName);
            setScanResult({
                success: true,
                message: '¡Puntos obtenidos!',
                points: result.points,
                groupName: result.groupName,
                groupEmoji: result.groupEmoji,
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

                {/* Debug helper for testing */}
                {window.location.hostname === 'localhost' && showManual && (
                    <div style={{ marginTop: 24, padding: 16, border: '1px dashed #666', borderRadius: 8 }}>
                        <p style={{ fontSize: '0.8rem', color: '#888', marginBottom: 8 }}>Debug Tools</p>
                        <button
                            type="button"
                            className="btn btn-outline"
                            style={{ fontSize: '0.7rem' }}
                            onClick={() => {
                                const groups = JSON.parse(localStorage.getItem('fp_groups') || '[]');
                                const secretRaw = localStorage.getItem('fp_admin_secret');
                                const secret = secretRaw ? JSON.parse(secretRaw) : null;

                                if (groups.length > 0 && secret) {
                                    // Pick random group to avoid cooldowns
                                    const g = groups[Math.floor(Math.random() * groups.length)];

                                    // Replicate generation logic
                                    const ts = Math.floor(Date.now() / 1000 / 30);
                                    const pts = g.visitPoints || 10;
                                    const type = 'visit';

                                    const data = {
                                        sid: g.id, ts, pts, type, name: g.name, emoji: g.emoji
                                    };
                                    // Simple HMAC
                                    const msg = `${g.id}|${ts}|${pts}|${type}`;
                                    const combined = secret + '|' + msg;
                                    let hash = 0;
                                    for (let i = 0; i < combined.length; i++) {
                                        const char = combined.charCodeAt(i);
                                        hash = ((hash << 5) - hash) + char;
                                        hash = hash & hash;
                                    }
                                    data.tok = Math.abs(hash).toString(16).padStart(8, '0');

                                    const payload = btoa(encodeURIComponent(JSON.stringify(data)));
                                    setManualInput(payload);
                                } else {
                                    alert('No groups or secret found in localStorage');
                                }
                            }}
                        >
                            🎲 Fill Valid Token (Random Group)
                        </button>
                    </div>
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
