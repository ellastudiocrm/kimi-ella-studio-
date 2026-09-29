'use client'

import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Image from 'next/image'
import { supabase } from '@/lib/supabase/client'

function LoginContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  // Só aceita caminhos internos, para o link de login não poder mandar para outro site
  const destino = searchParams.get('redirect') || ''
  const redirect = destino.startsWith('/') && !destino.startsWith('//') ? destino : '/dashboard'

  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [loading, setLoading] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setErro(null)

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
    })

    setLoading(false)

    if (error || !data.user) {
      setErro('Email ou senha incorretos')
      return
    }

    router.push(redirect)
    router.refresh()
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm rounded-3xl border border-ella-line/70 bg-white p-6 shadow-suave sm:p-8">
      <div className="mb-8 flex flex-col items-center text-center">
        <Image src="/marca/logo.png" alt="ELLA Studio" width={88} height={88} priority />
        <h1 className="mt-4 font-serif text-3xl font-medium">Área da equipe</h1>
        <p className="mt-1 text-sm text-ella-muted">Acesso restrito</p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {erro && (
          <p className="rounded-lg bg-red-50 p-3 text-sm text-red-600 text-center">
            {erro}
          </p>
        )}

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Email
          </label>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="seu@email.com"
            required
            className="campo"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Senha
          </label>
          <input
            type="password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            placeholder="••••••••"
            required
            className="campo"
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="btn-primario w-full"
        >
          {loading ? 'Entrando...' : 'Entrar'}
        </button>
      </form>

      </div>
    </div>
  )
}

export default function LoginPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-gray-500">Carregando...</p>
      </div>
    }>
      <LoginContent />
    </Suspense>
  )
}
