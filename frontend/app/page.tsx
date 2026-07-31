'use client'

import Link from 'next/link'

export default function HomePage() {
  return (
    <div className="flex flex-col min-h-screen px-6 py-12">
      {/* Logo / Header */}
      <div className="flex-1 flex flex-col items-center justify-center text-center mb-8">
        <h1 className="text-3xl font-bold tracking-tight text-ella-dark mb-2">
          ELLA Studio
        </h1>
        <p className="text-sm text-gray-500">
          Beleza & Estética — Valinhos, SP
        </p>
      </div>

      {/* Pergunta */}
      <div className="mb-8 text-center">
        <p className="text-lg font-medium text-gray-700">
          Bem-vinda! Você é:
        </p>
      </div>

      {/* Botões de cardápio */}
      <div className="space-y-4 mb-8">
        <Link
          href="/ella_studio"
          className="block w-full py-5 px-6 bg-ella-rose text-white rounded-2xl text-center font-semibold text-lg shadow-lg active:scale-[0.98] transition-transform touch-manipulation"
        >
          <span className="block text-2xl mb-1">👩</span>
          ELLA Studio
          <span className="block text-sm font-normal opacity-90 mt-1">
            Serviços femininos
          </span>
        </Link>

        <Link
          href="/ella_men"
          className="block w-full py-5 px-6 bg-ella-dark text-white rounded-2xl text-center font-semibold text-lg shadow-lg active:scale-[0.98] transition-transform touch-manipulation"
        >
          <span className="block text-2xl mb-1">👨</span>
          ELLA Men
          <span className="block text-sm font-normal opacity-90 mt-1">
            Serviços masculinos
          </span>
        </Link>
      </div>

      {/* Footer */}
      <div className="text-center text-xs text-gray-400 py-4">
        <p>Rua Santa Gertrudes, Valinhos — SP</p>
        <p className="mt-1">© 2026 ELLA Studio</p>
      </div>
    </div>
  )
}
