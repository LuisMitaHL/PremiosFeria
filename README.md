# FeriaPoints — University Fair Rewards System

A Progressive Web App (PWA) designed for university fairs, allowing attendees to scan QR codes at stands to earn points and redeem rewards.

## Features

- **PWA**: Installable on mobile devices with offline support.
- **Scanner**: Built-in QR scanner with manual fallback.
- **Admin Panel**: Manage stands, generate rotating QR codes, and view stats.
- **Security**: Time-based rotating QR codes (TOTP-style) with HMAC signatures to prevent sharing and replay attacks.
- **Data Persistence**: Uses `localStorage` for a self-contained demo (no external backend required).

## Tech Stack

- **Frontend**: React, Vite
- **Styling**: Vanilla CSS (CSS Modules/Variables)
- **Routing**: React Router DOM
- **Libraries**: `html5-qrcode` (Scanner), `qrcode.react` (Generator)

## Deployment

The application is containerized using Docker and served via Nginx.

### Prerequisites

- Docker and Docker Compose installed on your system.

### Running with Docker Compose

1.  Clone the repository (if not already done).
2.  Run the following command in the project root:

    ```bash
    docker compose up -d --build
    ```

3.  Access the application at:
    [http://localhost:8080](http://localhost:8080)

### Manual Build

To build and run locally without Docker:

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Build for production
npm run build
# Preview production build
npm run preview
```

## Developer Tools

When running on `localhost`, the scanner page includes a **"Developer Mode"** helper. This allows you to simulate scanning a valid QR code without needing a physical camera, which is useful for testing the rewards flow.
