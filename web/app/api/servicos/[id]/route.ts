import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    return NextResponse.json({ error: 'Não autenticado' }, { status: 401 })
  }

  const body = await request.json()
  const { preco_base, duracao_minutos, foto_url, ativo, cardapios } = body

  // Validação básica
  if (preco_base !== undefined && (typeof preco_base !== 'number' || preco_base < 0)) {
    return NextResponse.json({ error: 'Preço base inválido' }, { status: 400 })
  }
  if (duracao_minutos !== undefined && (typeof duracao_minutos !== 'number' || duracao_minutos < 1)) {
    return NextResponse.json({ error: 'Duração inválida' }, { status: 400 })
  }
  if (ativo !== undefined && typeof ativo !== 'boolean') {
    return NextResponse.json({ error: 'Ativo inválido' }, { status: 400 })
  }

  // Atualiza serviço
  const servicoUpdate: Record<string, unknown> = {}
  if (preco_base !== undefined) servicoUpdate.preco_base = preco_base
  if (duracao_minutos !== undefined) servicoUpdate.duracao_minutos = duracao_minutos
  if (foto_url !== undefined) servicoUpdate.foto_url = foto_url
  if (ativo !== undefined) servicoUpdate.ativo = ativo

  if (Object.keys(servicoUpdate).length > 0) {
    const { error } = await supabase
      .from('servicos')
      .update(servicoUpdate)
      .eq('id', params.id)

    if (error) {
      console.error('Erro ao atualizar serviço:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }
  }

  // Atualiza cardápios (array de { id, preco_final, ativo })
  if (Array.isArray(cardapios)) {
    for (const cardapio of cardapios) {
      if (cardapio.id && cardapio.preco_final !== undefined) {
        if (typeof cardapio.preco_final !== 'number' || cardapio.preco_final < 0) {
          return NextResponse.json({ error: 'Preço final inválido' }, { status: 400 })
        }

        const { error } = await supabase
          .from('servico_cardapios')
          .update({
            preco_final: cardapio.preco_final,
            ...(cardapio.ativo !== undefined ? { ativo: cardapio.ativo } : {}),
          })
          .eq('id', cardapio.id)
          .eq('servico_id', params.id)

        if (error) {
          console.error('Erro ao atualizar cardápio:', error)
          return NextResponse.json({ error: error.message }, { status: 500 })
        }
      }
    }
  }

  return NextResponse.json({ ok: true })
}
