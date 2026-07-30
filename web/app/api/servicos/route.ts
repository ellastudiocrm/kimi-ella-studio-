import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET() {
  const supabase = createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    return NextResponse.json({ error: 'Não autenticado' }, { status: 401 })
  }

  const { data: servicos, error } = await supabase
    .from('servicos')
    .select(`
      id,
      nome_tecnico,
      duracao_minutos,
      preco_base,
      percentual_sinal,
      anamnese_obrigatoria,
      ativo,
      foto_url,
      servico_cardapios (
        id,
        cardapio,
        nome_comercial,
        preco_final,
        ativo
      )
    `)
    .order('nome_tecnico')

  if (error) {
    console.error('Erro ao carregar serviços:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json(servicos)
}

export async function POST(request: Request) {
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
    cardapio,
    tipo_recurso_id,
    duracao_minutos,
    preco_base,
    preco_final,
    percentual_sinal,
    anamnese_obrigatoria,
  } = body

  // Validação
  if (!nome_tecnico || !nome_comercial || !cardapio || !tipo_recurso_id || !duracao_minutos) {
    return NextResponse.json({ error: 'Campos obrigatórios em falta' }, { status: 400 })
  }

  if (!['ella_studio', 'ella_men'].includes(cardapio)) {
    return NextResponse.json({ error: 'Cardápio inválido' }, { status: 400 })
  }

  if (typeof preco_base !== 'number' || preco_base < 0) {
    return NextResponse.json({ error: 'Preço base inválido' }, { status: 400 })
  }

  if (typeof duracao_minutos !== 'number' || duracao_minutos < 1) {
    return NextResponse.json({ error: 'Duração inválida' }, { status: 400 })
  }

  // Obtém empresa_id do utilizador autenticado (RLS valida perfil admin/gestor)
  const { data: usuario, error: usuarioError } = await supabase
    .from('usuarios_internos')
    .select('empresa_id, perfil')
    .eq('auth_user_id', user.id)
    .single()

  if (usuarioError || !usuario || !['admin', 'gestor'].includes(usuario.perfil)) {
    return NextResponse.json({ error: 'Sem permissão' }, { status: 403 })
  }

  const { data: servico, error: insertError } = await supabase
    .from('servicos')
    .insert({
      empresa_id: usuario.empresa_id,
      nome_tecnico,
      tipo_recurso_id,
      duracao_minutos,
      preco_base,
      percentual_sinal: percentual_sinal ?? 30,
      anamnese_obrigatoria: anamnese_obrigatoria ?? false,
      ativo: true,
    })
    .select('id')
    .single()

  if (insertError || !servico) {
    console.error('Erro ao criar serviço:', insertError)
    return NextResponse.json({ error: insertError?.message || 'Erro ao criar serviço' }, { status: 500 })
  }

  const { error: cardapioError } = await supabase.from('servico_cardapios').insert({
    servico_id: servico.id,
    cardapio,
    nome_comercial,
    preco_final: preco_final ?? preco_base,
    ativo: true,
  })

  if (cardapioError) {
    console.error('Erro ao criar cardápio:', cardapioError)
    return NextResponse.json({ error: cardapioError.message }, { status: 500 })
  }

  return NextResponse.json({ id: servico.id }, { status: 201 })
}
