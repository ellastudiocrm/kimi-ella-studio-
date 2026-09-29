'use server'

import { revalidatePath } from 'next/cache'
import { createSessionClient } from '@/lib/supabase/session'
import { FUSO_OFFSET } from '@/lib/painel'

// Ações da agenda. Todas usam a sessão de quem está logado: as funções do
// banco verificam o perfil (admin/gestor/recepção/profissional) antes de agir.

export type Resultado = { ok: true; id?: string; aviso?: string } | { ok: false; erro: string }

const MEIOS = ['pix', 'dinheiro', 'cartao_debito', 'cartao_credito'] as const
export type MeioPagamento = (typeof MEIOS)[number]

function mensagem(erro: unknown) {
  const texto = (erro as any)?.message ?? String(erro)
  // Mensagens do banco já vêm em português; só limpa prefixos técnicos
  return texto.replace(/^.*?ERROR:\s*/, '')
}

function atualizar() {
  revalidatePath('/dashboard', 'layout')
}

export async function registrarSinal(reservaId: string, meio: MeioPagamento): Promise<Resultado> {
  if (!MEIOS.includes(meio)) return { ok: false, erro: 'Forma de pagamento inválida' }
  const supabase = createSessionClient()

  const { data: cobranca, error } = await supabase
    .from('cobrancas')
    .select('id, valor_sinal, estado, transacoes(valor, estado, finalidade)')
    .eq('reserva_id', reservaId)
    .maybeSingle()
  if (error || !cobranca) return { ok: false, erro: 'Cobrança da reserva não encontrada' }

  const pago = ((cobranca as any).transacoes ?? [])
    .filter((t: any) => t.estado === 'pago' && ['sinal', 'saldo', 'pagamento_total'].includes(t.finalidade))
    .reduce((s: number, t: any) => s + Number(t.valor), 0)
  const falta = Math.round((Number(cobranca.valor_sinal) - pago) * 100) / 100

  if (falta <= 0) {
    const { error: e } = await supabase.rpc('confirmar_reserva', { p_reserva_id: reservaId })
    if (e) return { ok: false, erro: mensagem(e) }
  } else {
    const { error: e } = await supabase.rpc('registrar_pagamento_presencial', {
      p_cobranca_id: cobranca.id,
      p_valor: falta,
      p_meio: meio,
      p_finalidade: 'sinal',
      p_idempotencia_key: `painel-sinal-${reservaId}`,
    })
    if (e) return { ok: false, erro: mensagem(e) }
  }
  atualizar()
  return { ok: true }
}

export async function finalizarAtendimento(reservaId: string): Promise<Resultado> {
  const supabase = createSessionClient()
  const { error } = await supabase.rpc('finalizar_atendimento', { p_reserva_id: reservaId })
  if (error) return { ok: false, erro: mensagem(error) }
  atualizar()
  return { ok: true }
}

export async function cancelarReserva(reservaId: string, estadoAtual: string, motivo: string): Promise<Resultado> {
  const supabase = createSessionClient()
  const { data, error } =
    estadoAtual === 'pre_reserva'
      ? await supabase.rpc('cancelar_pre_reserva', { p_reserva_id: reservaId })
      : await supabase.rpc('cancelar_reserva', { p_reserva_id: reservaId, p_motivo: motivo || null })
  if (error) return { ok: false, erro: mensagem(error) }
  atualizar()
  return { ok: true, aviso: typeof data === 'string' ? data : undefined }
}

export async function criarBloqueio(dados: {
  profissionalId: string
  data: string
  horaInicio: string
  horaFim: string
  tipo: 'almoco' | 'folga' | 'imprevisto'
  motivo: string
}): Promise<Resultado> {
  const supabase = createSessionClient()
  const inicio = new Date(`${dados.data}T${dados.horaInicio}:00${FUSO_OFFSET}`)
  const fim = new Date(`${dados.data}T${dados.horaFim}:00${FUSO_OFFSET}`)
  if (!(fim > inicio)) return { ok: false, erro: 'A hora de fim tem de ser depois da hora de início' }

  const { data, error } = await supabase.rpc('criar_bloqueio_com_conflito', {
    p_profissional_id: dados.profissionalId,
    p_inicio: inicio.toISOString(),
    p_fim: fim.toISOString(),
    p_tipo: dados.tipo,
    p_motivo: dados.motivo || dados.tipo,
  })
  if (error) return { ok: false, erro: mensagem(error) }
  atualizar()
  const cancelados = Number((data as any)?.itens_cancelados ?? 0)
  return {
    ok: true,
    aviso: cancelados > 0 ? `${cancelados} atendimento(s) que estavam nesse horário foram cancelados.` : undefined,
  }
}

export async function removerBloqueio(bloqueioId: string): Promise<Resultado> {
  const supabase = createSessionClient()
  const { error } = await supabase.rpc('remover_bloqueio', { p_bloqueio_id: bloqueioId })
  if (error) return { ok: false, erro: mensagem(error) }
  atualizar()
  return { ok: true }
}

export async function buscarClientes(termo: string) {
  const supabase = createSessionClient()
  const limpo = termo.trim()
  if (limpo.length < 2) return []
  const digitos = limpo.replace(/\D/g, '')
  let q = supabase.from('clientes').select('id, nome, telefone_normalizado').limit(8).order('nome')
  q = digitos.length >= 4 ? q.ilike('telefone_normalizado', `%${digitos}%`) : q.ilike('nome', `%${limpo}%`)
  const { data } = await q
  return (data ?? []).map((c: any) => ({ id: c.id as string, nome: c.nome as string, telefone: c.telefone_normalizado as string }))
}

export async function criarAgendamento(dados: {
  cliente: { id: string } | { nome: string; telefone: string }
  servicoId: string
  profissionalId: string
  inicio: string
  cardapio: string
  chave: string
  sinal: MeioPagamento | null
}): Promise<Resultado> {
  const supabase = createSessionClient()
  const { data: empresaId } = await supabase.rpc('minha_empresa_id')
  if (!empresaId) return { ok: false, erro: 'Seu usuário não está ligado a uma empresa' }

  let clienteId: string
  if ('id' in dados.cliente) {
    clienteId = dados.cliente.id
  } else {
    const nome = dados.cliente.nome.trim()
    const d = dados.cliente.telefone.replace(/\D/g, '')
    const telefone = d.length === 10 || d.length === 11 ? `55${d}` : d
    if (nome.length < 2 || telefone.length < 12) return { ok: false, erro: 'Informe nome e WhatsApp com DDD do cliente' }

    const { data: existente } = await supabase
      .from('clientes')
      .select('id')
      .eq('telefone_normalizado', telefone)
      .maybeSingle()
    if (existente) {
      clienteId = existente.id
    } else {
      const { data: novo, error } = await supabase
        .from('clientes')
        .insert({ empresa_id: empresaId, nome, telefone_normalizado: telefone })
        .select('id')
        .single()
      if (error || !novo) return { ok: false, erro: `Não foi possível cadastrar o cliente: ${mensagem(error)}` }
      clienteId = novo.id
    }
  }

  const { data, error } = await supabase.rpc('criar_pre_reserva', {
    p_empresa_id: empresaId,
    p_cliente_id: clienteId,
    p_itens: [
      { servico_id: dados.servicoId, profissional_id: dados.profissionalId, inicio: dados.inicio, cardapio: dados.cardapio },
    ],
    p_idempotencia_key: dados.chave,
  })
  if (error) return { ok: false, erro: mensagem(error) }

  const reservaId = (data as any)?.reserva_id as string
  if (dados.sinal && reservaId) {
    const r = await registrarSinal(reservaId, dados.sinal)
    if (!r.ok) {
      atualizar()
      return { ok: true, id: reservaId, aviso: `Agendamento criado, mas o sinal não foi registrado: ${r.erro}` }
    }
  }
  atualizar()
  return { ok: true, id: reservaId }
}
