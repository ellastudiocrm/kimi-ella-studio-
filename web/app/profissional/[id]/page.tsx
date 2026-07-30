import { notFound } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'

interface Servico {
  id: string
  nome_tecnico: string
  duracao_minutos: number
  servico_cardapios: { cardapio: string; nome_comercial: string; preco_final: number }[]
}

interface Foto {
  id: string
  url: string
}

interface ProfissionalServicoRow {
  servico_id: string
  servicos: Servico[]
}

export default async function ProfissionalPublicPage({ params }: { params: { id: string } }) {
  const supabase = createClient()

  const { data: profissional, error } = await supabase
    .from('profissionais')
    .select('id, nome, foto_url, bio, especialidades')
    .eq('id', params.id)
    .eq('ativo', true)
    .single()

  if (error || !profissional) {
    notFound()
  }

  const [servicosResult, fotosResult] = await Promise.all([
    supabase
      .from('profissional_servicos')
      .select('servico_id, servicos(id, nome_tecnico, duracao_minutos, servico_cardapios(cardapio, nome_comercial, preco_final))')
      .eq('profissional_id', params.id),
    supabase
      .from('profissional_fotos')
      .select('id, url')
      .eq('profissional_id', params.id)
      .order('ordem'),
  ])

  const servicos = (servicosResult.data ?? [])
    .map((item: ProfissionalServicoRow) => item.servicos[0])
    .filter(Boolean) as Servico[]

  const fotos = (fotosResult.data ?? []) as Foto[]

  return (
    <main className="min-h-screen bg-gray-50 pb-24">
      {/* Cabeçalho */}
      <div className="relative bg-pink-600 pb-16 pt-8 text-white">
        <div className="mx-auto max-w-md px-4 text-center">
          <div className="relative mx-auto mb-4 h-28 w-28 overflow-hidden rounded-full border-4 border-white bg-pink-500 shadow-lg">
            {profissional.foto_url ? (
              <Image
                src={profissional.foto_url}
                alt={profissional.nome}
                fill
                className="object-cover"
                sizes="112px"
                priority
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-3xl font-bold">
                {profissional.nome.charAt(0).toUpperCase()}
              </div>
            )}
          </div>
          <h1 className="text-2xl font-bold">{profissional.nome}</h1>
          {profissional.especialidades && profissional.especialidades.length > 0 && (
            <p className="mt-1 text-sm text-pink-100">
              {profissional.especialidades.join(' • ')}
            </p>
          )}
        </div>
      </div>

      <div className="mx-auto max-w-md px-4">
        {/* Bio */}
        {profissional.bio && (
          <section className="-mt-8 rounded-xl bg-white p-5 shadow-sm ring-1 ring-gray-100">
            <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-500">Sobre</h2>
            <p className="whitespace-pre-line text-sm leading-relaxed text-gray-700">{profissional.bio}</p>
          </section>
        )}

        {/* Galeria */}
        {fotos.length > 0 && (
          <section className="mt-4 rounded-xl bg-white p-5 shadow-sm ring-1 ring-gray-100">
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500">Trabalhos</h2>
            <div className="grid grid-cols-2 gap-2">
              {fotos.map((foto) => (
                <div key={foto.id} className="relative aspect-square overflow-hidden rounded-lg bg-gray-100">
                  <Image
                    src={foto.url}
                    alt="Trabalho"
                    fill
                    className="object-cover"
                    sizes="(max-width: 768px) 50vw, 200px"
                  />
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Serviços */}
        <section className="mt-4 rounded-xl bg-white p-5 shadow-sm ring-1 ring-gray-100">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500">Serviços</h2>
          {servicos.length === 0 ? (
            <p className="text-sm text-gray-500">Nenhum serviço disponível.</p>
          ) : (
            <div className="space-y-2">
              {servicos.map((s) => {
                const cardapios = s.servico_cardapios
                const nome = cardapios[0]?.nome_comercial ?? s.nome_tecnico
                const preco = cardapios[0]?.preco_final ?? null

                return (
                  <div
                    key={s.id}
                    className="flex items-center justify-between rounded-lg border border-gray-100 p-3"
                  >
                    <div>
                      <p className="font-medium text-gray-900">{nome}</p>
                      <p className="text-xs text-gray-500">{s.duracao_minutos} min</p>
                    </div>
                    {preco !== null && (
                      <p className="text-sm font-semibold text-pink-600">
                        R$ {preco.toFixed(2)}
                      </p>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </section>
      </div>

      {/* Botão flutuante */}
      <div className="fixed bottom-0 left-0 right-0 border-t bg-white p-4">
        <div className="mx-auto max-w-md">
          <Link
            href={`/agendar?profissional=${profissional.id}`}
            className="block w-full rounded bg-pink-600 py-3.5 text-center text-sm font-semibold text-white hover:bg-pink-700 min-h-[44px]"
          >
            Agendar com {profissional.nome.split(' ')[0]}
          </Link>
        </div>
      </div>
    </main>
  )
}
