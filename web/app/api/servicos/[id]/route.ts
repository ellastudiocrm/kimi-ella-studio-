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
  const {
    nome_tecnico,
    nome_comercial,
    tipo_recurso_id,
    preco_base,
    preco_final,
    duracao_minutos,
    percentual_sinal,
    anamnese_obrigatoria,
    foto_url,
    ativo,
    cardapios,
  } = body

  // Validação básica
  if (preco_base !== undefined && (typeof preco_base !== 'number' || preco_base < 0)) {
    return NextResponse.json({ error: 'Preço base inválido' }, { status: 400 })
  }
  if (preco_final !== undefined && (typeof preco_final !== 'number' || preco_final < 0)) {
    return NextResponse.json({ error: 'Preço final inválido' }, { status: 400 })
  }
  if (duracao_minutos !== undefined && (typeof duracao_minutos !== 'number' || duracao_minutos < 1)) {
    return NextResponse.json({ error: 'Duração inválida' }, { status: 400 })
  }
  if (percentual_sinal !== undefined && (typeof percentual_sinal !== 'number' || percentual_sinal < 0)) {
    return NextResponse.json({ error: 'Percentual de sinal inválido' }, { status: 400 })
  }

  // Atualiza serviço
  const servicoUpdate: Record<string, unknown> = {}
  if (nome_tecnico !== undefined) servicoUpdate.nome_tecnico = nome_tecnico
  if (tipo_recurso_id !== undefined) servicoUpdate.tipo_recurso_id = tipo_recurso_id
  if (preco_base !== undefined) servicoUpdate.preco_base = preco_base
  if (duracao_minutos !== undefined) servicoUpdate.duracao_minutos = duracao_minutos
  if (percentual_sinal !== undefined) servicoUpdate.percentual_sinal = percentual_sinal
  if (anamnese_obrigatoria !== undefined) servicoUpdate.anamnese_obrigatoria = anamnese_obrigatoria
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

  // Atualiza cardápios (array de { id, preco_final, ativo, nome_comercial })
  if (Array.isArray(cardapios)) {
    for (const cardapio of cardapios) {
      if (cardapio.id) {
        const cardapioUpdate: Record<string, unknown> = {}
        if (cardapio.preco_final !== undefined) {
          if (typeof cardapio.preco_final !== 'number' || cardapio.preco_final < 0) {
            return NextResponse.json({ error: 'Preço final inválido' }, { status: 400 })
          }
          cardapioUpdate.preco_final = cardapio.preco_final
        }
        if (cardapio.nome_comercial !== undefined) cardapioUpdate.nome_comercial = cardapio.nome_comercial
        if (cardapio.ativo !== undefined) cardapioUpdate.ativo = cardapio.ativo

        if (Object.keys(cardapioUpdate).length > 0) {
          const { error } = await supabase
            .from('servico_cardapios')
            .update(cardapioUpdate)
            .eq('id', cardapio.id)
            .eq('servico_id', params.id)

          if (error) {
            console.error('Erro ao atualizar cardápio:', error)
            return NextResponse.json({ error: error.message }, { status: 500 })
          }
        }
      }
    }
  }

  // Atualização simplificada de um único cardápio pelo nome_comercial/preco_final
  if (nome_comercial !== undefined || preco_final !== undefined) {
    const { data: cardapiosExistentes } = await supabase
      .from('servico_cardapios')
      .select('id')
      .eq('servico_id', params.id)

    if (cardapiosExistentes && cardapiosExistentes.length > 0) {
      const cardapioUpdate: Record<string, unknown> = {}
      if (nome_comercial !== undefined) cardapioUpdate.nome_comercial = nome_comercial
      if (preco_final !== undefined) {
        if (typeof preco_final !== 'number' || preco_final < 0) {
          return NextResponse.json({ error: 'Preço final inválido' }, { status: 400 })
        }
        cardapioUpdate.preco_final = preco_final
      }

      const { error } = await supabase
        .from('servico_cardapios')
        .update(cardapioUpdate)
        .eq('id', cardapiosExistentes[0].id)

      if (error) {
        console.error('Erro ao atualizar cardápio principal:', error)
        return NextResponse.json({ error: error.message }, { status: 500 })
      }
    }
  }

  return NextResponse.json({ ok: true })
}
