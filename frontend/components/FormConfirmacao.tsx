'use client'

import { useRef, useState } from 'react'
import Link from 'next/link'
import Passos from '@/components/Passos'
import ResumoServico from '@/components/ResumoServico'
import { IconeCheck, IconeVoltar, IconeWhatsApp } from '@/components/Icones'
import {
  CONTATO,
  formatarDataLonga,
  formatarHora,
  formatarPreco,
  linkWhatsApp,
  type Cardapio,
} from '@/lib/marca'
import type { ServicoCatalogo } from '@/lib/catalogo'
import type { PreReservaResponse } from '@/types'

function mascararTelefone(valor: string) {
  const d = valor.replace(/\D/g, '').slice(0, 11)
  if (d.length <= 2) return d
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
}

export default function FormConfirmacao({
  cardapio,
  servico,
  profissional,
  data,
  hora,
  empresaId,
}: {
  cardapio: Cardapio
  servico: ServicoCatalogo
  profissional: { id: string; nome: string }
  data: string
  hora: string
  empresaId: string
}) {
  const [nome, setNome] = useState('')
  const [telefone, setTelefone] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [resultado, setResultado] = useState<PreReservaResponse | null>(null)
  // Mesma chave em novas tentativas: evita reserva duplicada se a pessoa clicar duas vezes
  const chave = useRef(`web-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`)

  const quando = `${formatarDataLonga(data)} às ${formatarHora(hora)}`
  const sinal = (servico.preco * servico.percentualSinal) / 100
  const digitos = telefone.replace(/\D/g, '')
  const valido = nome.trim().length >= 3 && digitos.length >= 10

  async function confirmar(e: React.FormEvent) {
    e.preventDefault()
    if (!valido) {
      setErro('Preencha o seu nome e um WhatsApp com DDD.')
      return
    }
    setErro(null)
    setEnviando(true)
    try {
      const resposta = await fetch('/api/pre-reserva', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          empresa_id: empresaId,
          cliente_nome: nome.trim(),
          cliente_telefone: digitos,
          itens: [{ servico_id: servico.id, profissional_id: profissional.id, inicio: hora, cardapio }],
          idempotencia_key: chave.current,
        }),
      })
      const corpo = await resposta.json()
      if (!resposta.ok) {
        setErro(
          'Não conseguimos concluir a reserva. Esse horário pode ter acabado de ser ocupado — volte e escolha outro, ou fale com a gente pelo WhatsApp.'
        )
      } else {
        setResultado(corpo)
        window.scrollTo({ top: 0, behavior: 'smooth' })
      }
    } catch {
      setErro('Sem conexão no momento. Verifique a internet e tente de novo.')
    }
    setEnviando(false)
  }

  if (resultado) {
    const confirmada = resultado.estado === 'confirmada'
    return (
      <div className="container-ella py-12 sm:py-16">
        <div className="mx-auto max-w-xl text-center">
          <span className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-ella-rose text-white shadow-suave">
            <IconeCheck className="h-8 w-8" />
          </span>
          <h1 className="mt-6 font-serif text-4xl font-medium">
            {confirmada ? 'Reserva confirmada!' : 'Horário reservado!'}
          </h1>
          <p className="mt-3 text-ella-muted">
            {confirmada
              ? `Obrigada, ${nome.split(' ')[0]}! Te esperamos no ELLA Studio.`
              : `Obrigada, ${nome.split(' ')[0]}! Seu horário fica guardado por 30 minutos. Chame o estúdio no WhatsApp para combinar o sinal e confirmar.`}
          </p>
        </div>

        <div className="mx-auto mt-8 max-w-md">
          <ResumoServico servico={servico} cardapio={cardapio} profissional={profissional.nome} quando={quando} />
          {!confirmada && resultado.valor_sinal > 0 && (
            <p className="mt-4 rounded-2xl bg-ella-card p-4 text-center text-sm">
              Sinal para confirmar: <strong>{formatarPreco(resultado.valor_sinal)}</strong>
            </p>
          )}
          <div className="mt-6 flex flex-col gap-3">
            <a
              href={linkWhatsApp(
                `Olá! Acabei de reservar ${servico.nome} para ${quando}. Meu nome é ${nome.trim()}.`
              )}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primario"
            >
              <IconeWhatsApp className="h-4 w-4" />
              Falar com o estúdio no WhatsApp
            </a>
            <Link href="/" className="btn-secundario">
              Voltar ao início
            </Link>
          </div>
          <p className="mt-6 text-center text-xs text-ella-muted">
            {CONTATO.endereco} · {CONTATO.bairro}
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="container-ella py-8 sm:py-12">
      <Link
        href={`/agendar?profissional=${profissional.id}&servico=${encodeURIComponent(servico.nomeTecnico)}&cardapio=${cardapio}`}
        className="mb-6 inline-flex items-center gap-2 text-sm text-ella-muted hover:text-ella-rose"
      >
        <IconeVoltar className="h-4 w-4" />
        Trocar horário
      </Link>
      <Passos atual={3} />

      <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_340px]">
        <div className="order-2 lg:order-1">
          <h1 className="font-serif text-3xl font-medium sm:text-4xl">Quase lá! Seus dados</h1>
          <p className="mt-2 text-ella-muted">Usamos só para confirmar o seu horário.</p>

          <form onSubmit={confirmar} className="mt-8 max-w-lg space-y-5" noValidate>
            <div>
              <label htmlFor="nome" className="mb-1.5 block text-sm font-medium">
                Nome completo
              </label>
              <input
                id="nome"
                type="text"
                autoComplete="name"
                value={nome}
                onChange={(e) => setNome(e.target.value)}
                placeholder="Como podemos te chamar?"
                className="campo"
              />
            </div>
            <div>
              <label htmlFor="telefone" className="mb-1.5 block text-sm font-medium">
                WhatsApp
              </label>
              <input
                id="telefone"
                type="tel"
                inputMode="numeric"
                autoComplete="tel-national"
                value={telefone}
                onChange={(e) => setTelefone(mascararTelefone(e.target.value))}
                placeholder="(19) 99999-9999"
                className="campo"
              />
            </div>

            {servico.percentualSinal > 0 && (
              <div className="rounded-2xl bg-ella-card p-4 text-sm leading-relaxed">
                Para garantir o horário pedimos um sinal de{' '}
                <strong>
                  {formatarPreco(sinal)} ({servico.percentualSinal}%)
                </strong>
                , descontado do valor do serviço. Depois de confirmar, é só chamar o estúdio no WhatsApp para
                combinar o pagamento.
              </div>
            )}

            {erro && (
              <p role="alert" className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
                {erro}
              </p>
            )}

            <button type="submit" disabled={enviando} className="btn-primario w-full sm:w-auto sm:min-w-[260px]">
              {enviando ? 'Reservando…' : 'Confirmar agendamento'}
            </button>
            <p className="text-xs text-ella-muted">
              Ao confirmar, você concorda com a nossa política de cancelamento.
            </p>
          </form>
        </div>

        <div className="order-1 lg:order-2">
          <ResumoServico servico={servico} cardapio={cardapio} profissional={profissional.nome} quando={quando} />
        </div>
      </div>
    </div>
  )
}
