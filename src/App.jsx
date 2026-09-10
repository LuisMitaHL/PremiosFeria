import React from 'react';
import { Routes, Route, NavLink, useLocation, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/AuthContext.jsx';
import { Compass, Home, Trophy, ScanLine, Gift, Star } from 'lucide-react';

// Pages
import Welcome from './pages/Welcome.jsx';
import Register from './pages/Register.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Scanner from './pages/Scanner.jsx';
import Leaderboard from './pages/Leaderboard.jsx';
import Rewards from './pages/Rewards.jsx';
import AdminLogin from './pages/admin/AdminLogin.jsx';
import AdminDashboard from './pages/admin/AdminDashboard.jsx';
import QRDisplay from './pages/admin/QRDisplay.jsx';
import OrganizerLogin from './pages/organizer/OrganizerLogin.jsx';
import OrganizerPanel from './pages/organizer/OrganizerPanel.jsx';

function BackgroundDecorations() {
    return (
        <div className="bg-ornaments">
            <img src="/images/backgrounds/Recurso1.svg" className="bg-ornament ornament-1" alt="" />
            <img src="/images/backgrounds/Recurso2.svg" className="bg-ornament ornament-2" alt="" />
            <img src="/images/backgrounds/Recurso3.svg" className="bg-ornament ornament-3" alt="" />
        </div>
    );
}

function AppLayout({ children }) {
    const { participant } = useAuth();
    const location = useLocation();

    // La barra del estudiante no aparece en bienvenida, registro, ni en los
    // paneles de stand y organizador.
    const hideNav =
        ['/', '/register'].includes(location.pathname) ||
        location.pathname.startsWith('/admin') ||
        location.pathname.startsWith('/organizador');

    if (hideNav) return <>{children}</>;

    return (
        <>
            <BackgroundDecorations />
            {/* Header */}
            <header className="app-header">
                <div className="header-content">
                    <div className="logo-icon"><img src="/images/logo/LOGO.svg" alt="Logo" style={{ width: 120, height: 'auto' }} /></div>
                    {participant && (
                        <div className="header-points">
                            <span className="pts-icon"><Star size={14} /></span>
                            <span>{participant.points}</span>
                        </div>
                    )}
                </div>
            </header>

            {/* Page Content */}
            {children}

            {/* Bottom Navigation */}
            <nav className="bottom-nav">
                <div className="nav-items">
                    <NavLink to="/dashboard" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon"><Home size={20} /></span>
                        <span>Inicio</span>
                    </NavLink>
                    <NavLink to="/leaderboard" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon"><Trophy size={20} /></span>
                        <span>Ranking</span>
                    </NavLink>
                    <NavLink to="/scan" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon"><ScanLine size={22} /></span>
                        <span>Scan</span>
                    </NavLink>
                    <NavLink to="/rewards" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon"><Gift size={20} /></span>
                        <span>Premios</span>
                    </NavLink>
                </div>
            </nav>
        </>
    );
}

// Protected route wrapper for participants
function RequireAuth({ children }) {
    const { participant, participantLoading } = useAuth();
    if (participantLoading) return null;
    if (!participant) return <Navigate to="/" replace />;
    return children;
}

function AppRoutes() {
    return (
        <AppLayout>
            <Routes>
                <Route path="/" element={<Welcome />} />
                <Route path="/register" element={<Register />} />
                <Route path="/dashboard" element={<RequireAuth><Dashboard /></RequireAuth>} />
                <Route path="/scan" element={<RequireAuth><Scanner /></RequireAuth>} />
                <Route path="/leaderboard" element={<RequireAuth><Leaderboard /></RequireAuth>} />
                <Route path="/rewards" element={<RequireAuth><Rewards /></RequireAuth>} />
                <Route path="/admin/login" element={<AdminLogin />} />
                <Route path="/admin" element={<AdminDashboard />} />
                <Route path="/admin/qr/:groupId" element={<QRDisplay />} />
                {/* El panel del organizador vive en la misma aplicación, en su
                    propia dirección, y NO se enlaza desde ninguna pantalla del
                    estudiante ni del stand (spec 017, R10). Eso no es el
                    control de acceso -- lo es la base de datos -- solo evita
                    que trescientas personas encuentren una pantalla que no es
                    para ellas. */}
                <Route path="/organizador/entrar" element={<OrganizerLogin />} />
                <Route path="/organizador" element={<OrganizerPanel />} />
                <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
        </AppLayout>
    );
}

export default function App() {
    return (
        <AuthProvider>
            <AppRoutes />
        </AuthProvider>
    );
}
