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
