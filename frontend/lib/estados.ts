// Rótulos e cores dos estados de reserva, usados na agenda e no atendimento.

export const ESTADOS: Record<string, { rotulo: string; cor: string; bloco: string }> = {
  pre_reserva: {
    rotulo: 'Aguardando sinal',
    cor: 'bg-amber-50 text-amber-800 ring-amber-200',
    bloco: 'border-l-amber-400 bg-amber-50',
  },
  pagamento_em_revisao: {
    rotulo: 'Pagamento em revisão',
    cor: 'bg-orange-50 text-orange-800 ring-orange-200',
    bloco: 'border-l-orange-400 bg-orange-50',
  },
  confirmada: {
    rotulo: 'Confirmada',
    cor: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
    bloco: 'border-l-emerald-500 bg-emerald-50',
  },
  realizada: {
    rotulo: 'Realizada',
    cor: 'bg-stone-100 text-stone-700 ring-stone-200',
    bloco: 'border-l-stone-400 bg-stone-100',
  },
  cancelada: {
    rotulo: 'Cancelada',
    cor: 'bg-rose-50 text-rose-700 ring-rose-200',
    bloco: 'border-l-rose-300 bg-rose-50/60 line-through opacity-70',
  },
  expirada: {
    rotulo: 'Expirada',
    cor: 'bg-stone-100 text-stone-500 ring-stone-200',
    bloco: 'border-l-stone-300 bg-stone-50 opacity-60',
  },
  no_show: {
    rotulo: 'Não compareceu',
    cor: 'bg-rose-50 text-rose-700 ring-rose-200',
    bloco: 'border-l-rose-400 bg-rose-50',
  },
}

export function estado(e: string) {
  return ESTADOS[e] ?? { rotulo: e, cor: 'bg-stone-100 text-stone-600 ring-stone-200', bloco: 'border-l-stone-300 bg-white' }
}

// Reservas que ainda ocupam a agenda
export function ocupaAgenda(e: string) {
  return e === 'pre_reserva' || e === 'confirmada' || e === 'pagamento_em_revisao' || e === 'realizada'
}

export const MEIOS = [
  { valor: 'pix', rotulo: 'Pix' },
  { valor: 'dinheiro', rotulo: 'Dinheiro' },
  { valor: 'cartao_debito', rotulo: 'Débito' },
  { valor: 'cartao_credito', rotulo: 'Crédito' },
] as const

export const TIPOS_BLOQUEIO: Record<string, string> = {
  almoco: 'Almoço',
  folga: 'Folga',
  imprevisto: 'Imprevisto',
}

export function telefoneExibicao(t: string) {
  const d = t.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return t
}

export function linkWhatsCliente(t: string) {
  const d = t.replace(/\D/g, '')
  return `https://wa.me/${d.length <= 11 ? `55${d}` : d}`
}
