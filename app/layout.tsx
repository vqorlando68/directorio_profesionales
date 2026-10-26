import './globals.css';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Directorio de Profesionales | TEKER Medical Suite',
  description: 'Directorio escalable de profesionales de salud con disponibilidad en tiempo real',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
