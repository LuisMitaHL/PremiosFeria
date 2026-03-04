import React from 'react';
import { Routes, Route, NavLink, useLocation, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/AuthContext.jsx';

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

function AppLayout({ children }) {
    const { participant } = useAuth();
    const location = useLocation();

    // Don't show nav on welcome, register, admin, or QR display pages
    const hideNav = ['/', '/register'].includes(location.pathname) || location.pathname.startsWith('/admin');

    if (hideNav) return <>{children}</>;

    return (
        <>
            {/* Header */}
            <header className="app-header">
                <div className="header-content">
                    <div className="header-logo">
                        <div className="logo-icon">🎪</div>
                        <span>Community Quest</span>
                    </div>
                    {participant && (
                        <div className="header-points">
                            <span className="pts-icon">⭐</span>
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
                        <span className="nav-icon">🏠</span>
                        <span>Inicio</span>
                    </NavLink>
                    <NavLink to="/leaderboard" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon">🏆</span>
                        <span>Ranking</span>
                    </NavLink>
                    <NavLink to="/scan" className="nav-item scan-btn">
                        <span className="nav-icon">📸</span>
                        <span>Scan</span>
                    </NavLink>
                    <NavLink to="/rewards" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
                        <span className="nav-icon">🎁</span>
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
