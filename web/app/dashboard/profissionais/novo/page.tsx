'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'

export default function NovoProfissionalPage() {
  const router = useRouter()
  const [nome, setNome] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSalvando(true)
    setErro(null)

    const res = await fetch('/api/profissionais', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nome }),
    })

    setSalvando(false)

    if (!res.ok) {
      const data = await res.json()
      setErro(data.error || 'Erro ao criar profissional')
      return
    }

    const json = await res.json()
    router.push(`/dashboard/profissionais/${json.id}`)
  }

  return (
    <div>
      <h2 className="text-xl font-bold text-gray-900 md:text-2xl">Novo profissional</h2>
      <form onSubmit={handleSubmit} className="mt-6 max-w-lg rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100">
        {erro && <p className="mb-4 text-sm text-red-600">{erro}</p>}
        <div>
          <label className="block text-sm font-medium text-gray-700">Nome</label>
          <input
            type="text"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
            required
            className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm min-h-[44px]"
          />
        </div>
        <button
          type="submit"
          disabled={salvando}
          className="mt-4 w-full rounded bg-pink-600 py-3 text-sm font-semibold text-white hover:bg-pink-700 disabled:opacity-50 min-h-[44px]"
        >
          {salvando ? 'A criar...' : 'Criar profissional'}
        </button>
      </form>
    </div>
  )
}
