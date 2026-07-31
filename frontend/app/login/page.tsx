'use client'

import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { supabase } from '@/lib/supabase/client'

function LoginContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const redirect = searchParams.get('redirect') || '/dashboard'

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
    <div className="min-h-screen px-6 py-12 flex flex-col">
      <div className="flex-1 flex flex-col items-center justify-center text-center mb-10">
        <h1 className="text-3xl font-bold tracking-tight text-ella-dark mb-2">
          ELLA Studio
        </h1>
        <p className="text-sm text-gray-500">Acesso restrito</p>
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
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-ella-rose focus:outline-none text-base min-h-[44px]"
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
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-ella-rose focus:outline-none text-base min-h-[44px]"
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="w-full py-4 bg-ella-rose text-white rounded-xl text-center font-semibold text-lg shadow-lg active:scale-[0.98] transition-transform disabled:opacity-50 min-h-[44px]"
        >
          {loading ? 'Entrando...' : 'Entrar'}
        </button>
      </form>

      <div className="mt-6 text-center">
        <Link href="/" className="text-sm text-gray-500 hover:text-ella-rose">
          ← Voltar ao site
        </Link>
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
