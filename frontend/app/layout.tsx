import type { Metadata, Viewport } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'ELLA Studio — Agendamento Online',
  description: 'Agende seu horário no ELLA Studio de beleza e estética em Valinhos',
}

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="pt-BR">
      <body className="bg-ella-light text-ella-dark min-h-screen">
        <main className="mx-auto max-w-md min-h-screen bg-white shadow-xl">
          {children}
        </main>
      </body>
    </html>
  )
}
