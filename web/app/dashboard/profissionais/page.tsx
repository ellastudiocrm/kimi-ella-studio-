import { redirect } from 'next/navigation'
import Link from 'next/link'
import Image from 'next/image'
import { createClient } from '@/lib/supabase/server'

interface Profissional {
  id: string
  nome: string
  foto_url: string | null
  bio: string | null
  especialidades: string[]
  ativo: boolean
}

export default async function ProfissionaisPage() {
  const supabase = createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/auth/login')
  }

  const { data: profissionais, error } = await supabase
    .from('profissionais')
    .select('id, nome, foto_url, bio, especialidades, ativo')
    .order('nome')

  if (error) {
    console.error('Erro ao carregar profissionais:', error)
    return <p className="text-red-600">Erro ao carregar profissionais: {error.message}</p>
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-xl font-bold text-gray-900 md:text-2xl">Profissionais</h2>
        <Link
          href="/dashboard/profissionais/novo"
          className="rounded bg-pink-600 px-4 py-2 text-sm font-semibold text-white hover:bg-pink-700 min-h-[44px] flex items-center"
        >
          + Novo
        </Link>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {(profissionais ?? []).map((p: Profissional) => (
          <Link
            key={p.id}
            href={`/dashboard/profissionais/${p.id}`}
            className="flex items-center gap-4 rounded-lg bg-white p-4 shadow-sm ring-1 ring-gray-100 hover:shadow-md"
          >
            <div className="relative h-16 w-16 flex-shrink-0 overflow-hidden rounded-full bg-gray-100">
              {p.foto_url ? (
                <Image
                  src={p.foto_url}
                  alt={p.nome}
                  fill
                  className="object-cover"
                  sizes="64px"
                />
              ) : (
                <div className="flex h-full w-full items-center justify-center text-lg font-bold text-gray-400">
                  {p.nome.charAt(0).toUpperCase()}
                </div>
              )}
            </div>
            <div className="min-w-0 flex-1">
              <h3 className="truncate font-semibold text-gray-900">{p.nome}</h3>
              <p className="truncate text-sm text-gray-500">
                {p.especialidades?.length > 0
                  ? p.especialidades.join(', ')
                  : 'Sem especialidades'}
              </p>
              <span
                className={`mt-1 inline-block rounded px-2 py-0.5 text-xs font-medium ${
                  p.ativo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                }`}
              >
                {p.ativo ? 'Ativo' : 'Inativo'}
              </span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
