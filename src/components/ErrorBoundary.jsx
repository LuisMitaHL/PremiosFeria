import { Component } from 'react';
import { AlertTriangle, RotateCcw } from 'lucide-react';

// La ultima red.
//
// Cada pantalla ya atrapa los fallos de sus lecturas y los cuenta en su sitio.
// Lo que no atrapa nadie es una excepcion mientras React DIBUJA: ahi React
// desmonta el arbol entero y lo que queda es una pagina en blanco. Un asistente
// en medio de la feria no sabe que eso se arregla recargando, y no hay nada en
// pantalla que se lo diga.
//
// Tiene que ser una clase: React no da equivalente en hooks para esto.
export default class ErrorBoundary extends Component {
    constructor(props) {
        super(props);
        this.state = { fallo: false };
    }

    static getDerivedStateFromError() {
        return { fallo: true };
    }

    componentDidCatch(error, info) {
        // A la consola, que es donde sirve. No se le enseña a nadie: un rastro
        // de pila no le dice nada a quien esta parado frente a un stand.
        console.error('Fallo al dibujar:', error, info?.componentStack);
    }

    render() {
        if (!this.state.fallo) return this.props.children;

        return (
            <div className="page">
                <div className="container" style={{ paddingTop: 80 }}>
                    <div className="empty-state">
                        <div className="empty-icon">
                            <AlertTriangle size={40} />
                        </div>
                        <p>Algo se rompió en esta pantalla.</p>
                        <p className="empty-hint">
                            Tus puntos y tu historial están guardados: no se pierde nada al
                            volver a cargar.
                        </p>
                        <button
                            className="btn btn-primary"
                            style={{ marginTop: 20 }}
                            onClick={() => window.location.reload()}
                        >
                            <RotateCcw size={16} /> Volver a cargar
                        </button>
                    </div>
                </div>
            </div>
        );
    }
}
