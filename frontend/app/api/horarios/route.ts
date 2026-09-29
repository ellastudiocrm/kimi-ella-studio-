import { NextResponse } from 'next/server'
import { supabasePublico } from '@/lib/supabase/publico'

export async function POST(request: Request) {
  try {
    const body = await request.json()

    // listar_horarios_disponiveis tem EXECUTE liberado para anon: não precisa da chave secreta
    const { data, error } = await supabasePublico.rpc('listar_horarios_disponiveis', {
      p_empresa_id: body.empresa_id,
      p_servico_id: body.servico_id,
      p_profissional_id: body.profissional_id,
      p_data: body.data,
      p_cardapio: body.cardapio || 'ella_studio',
      p_intervalo_minutos: body.intervalo_minutos || 30,
      p_limite_slots: body.limite_slots || 96,
    })

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 400 }
      )
    }

    return NextResponse.json(data)
  } catch (err) {
    return NextResponse.json(
      { error: 'Erro interno no servidor' },
      { status: 500 }
    )
  }
}
