import { useState, useEffect, useRef } from 'react';
import { Loader, PartyPopper, AlertTriangle, X } from 'lucide-react';
import { issueClaimCode, pollMyClaimCode } from '../lib/api.js';

// The attendee is standing in front of the stand watching this screen, so it
// asks every two seconds. Anything slower reads as broken when the person
// opposite has just tapped confirm. It runs only while the modal is open and
// asks about one exchange, so the cost is negligible -- and asking is also what
// keeps the code alive (spec 018).
const POLL_MS = 2000;

export default function ClaimCodeModal({ onClose, onClaimed }) {
    const [code, setCode] = useState('');
    const [state, setState] = useState('loading');
    const [result, setResult] = useState(null);
    const [error, setError] = useState('');
    const closedRef = useRef(false);

    // Held in a ref so the effect below depends on nothing. A parent that
    // re-renders would otherwise re-run it, and re-running means issuing a
    // second code -- which invalidates the one the attendee is showing.
    const onClaimedRef = useRef(onClaimed);
    onClaimedRef.current = onClaimed;

    useEffect(() => {
        let timer = null;
        // Reset on every mount. React mounts, unmounts and remounts effects in
        // development; without this the flag stays true from the first cleanup
        // and the polling callback returns early forever -- the modal would sit
        // showing a code that had already been used, and say nothing.
        closedRef.current = false;

        let failures = 0;

        const start = async () => {
            try {
                const issued = await issueClaimCode();
                // Discard a result that arrived after this effect was torn down,
                // or a remount ends up with two polling loops.
                if (closedRef.current) return;
                if (issued?.error) {
                    setError(issued.error);
                    setState('error');
                    return;
                }
                setCode(issued.code);
                setState('live');

                timer = setInterval(async () => {
                    if (closedRef.current) return;
                    try {
                        const poll = await pollMyClaimCode();
                        if (poll?.state === 'used') {
                            clearInterval(timer);
                            setResult(poll);
                            setState('used');
                            onClaimedRef.current?.();
                        } else if (poll?.state === 'expired' || poll?.state === 'none') {
                            clearInterval(timer);
                            setState('expired');
                        }
                        failures = 0;
                    } catch {
                        // One dropped request is not a verdict: the exchange
                        // either happened completely or not at all, and this
                        // screen catches up when the network returns. A run of
                        // them is different -- silence here once hid a bug that
                        // left the modal showing a code already spent.
                        failures += 1;
                        if (failures >= 5) {
                            clearInterval(timer);
                            setError('Perdimos la conexión. Cierra y vuelve a abrir tu código.');
                            setState('error');
                        }
                    }
                }, POLL_MS);
            } catch (err) {
                setError(err.message);
                setState('error');
            }
        };

        start();
        return () => {
            closedRef.current = true;
            if (timer) clearInterval(timer);
        };
    }, []);

    return (
        <div className="modal-overlay" onClick={onClose}>
            <div className="modal-content claim-modal" onClick={(e) => e.stopPropagation()}>
                <button className="modal-close" onClick={onClose} aria-label="Cerrar">
                    <X size={18} />
                </button>

                {state === 'loading' && (
                    <div className="empty-state">
                        <Loader size={28} className="spin-icon" />
                    </div>
                )}

                {state === 'live' && (
                    <>
                        <h2 className="claim-title">Muestra este código</h2>
                        <p className="claim-sub">
                            En el stand del premio que quieres. Ellos lo ingresan y confirman la
                            entrega.
                        </p>
                        <div className="claim-code">{code}</div>
                        <p className="empty-hint">
                            Sirve una sola vez. Mientras esta pantalla esté abierta, sigue vigente.
                        </p>
                    </>
                )}

                {state === 'used' && (
                    <div className="claim-done">
                        <PartyPopper size={40} />
                        <h2 className="claim-title">¡Premio entregado!</h2>
                        {result?.reward && <p className="claim-sub">{result.reward}</p>}
                        <div className="claim-balance">{result?.points} pts</div>
                        <p className="empty-hint">Tu nuevo saldo</p>
                        <button className="btn btn-primary btn-full" onClick={onClose}>
                            Listo
                        </button>
                    </div>
                )}

                {state === 'expired' && (
                    <div className="empty-state">
                        <p>El código venció.</p>
                        <p className="empty-hint">
                            Vuelve a abrir esta pantalla para obtener uno nuevo.
                        </p>
                        <button className="btn btn-primary btn-full" onClick={onClose}>
                            Cerrar
                        </button>
                    </div>
                )}

                {state === 'error' && (
                    <div className="empty-state">
                        <p className="form-error">
                            <AlertTriangle size={14} /> {error}
                        </p>
                        <button className="btn btn-primary btn-full" onClick={onClose}>
                            Cerrar
                        </button>
                    </div>
                )}
            </div>
        </div>
    );
}
