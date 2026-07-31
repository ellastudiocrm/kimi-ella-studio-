import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase/server'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const {
      empresa_id,
      cliente_nome,
      cliente_telefone,
      itens,
      idempotencia_key,
    } = body

    if (!empresa_id || !cliente_nome || !cliente_telefone || !Array.isArray(itens) || itens.length === 0) {
      return NextResponse.json(
        { error: 'Dados incompletos' },
        { status: 400 }
      )
    }

    // Buscar cliente existente pelo telefone
    const { data: clienteExistente, error: clienteBuscaError } = await supabaseAdmin
      .from('clientes')
      .select('id')
      .eq('empresa_id', empresa_id)
      .eq('telefone_normalizado', cliente_telefone)
      .single()

    let cliente_id: string

    if (clienteExistente) {
      cliente_id = clienteExistente.id
    } else {
      const { data: novoCliente, error: clienteInsertError } = await supabaseAdmin
        .from('clientes')
        .insert({
          empresa_id,
          nome: cliente_nome,
          telefone_normalizado: cliente_telefone,
        })
        .select('id')
        .single()

      if (clienteInsertError || !novoCliente) {
        console.error('Erro ao criar cliente:', clienteInsertError)
        return NextResponse.json(
          { error: clienteInsertError?.message || 'Erro ao criar cliente' },
          { status: 500 }
        )
      }

      cliente_id = novoCliente.id
    }

    const { data, error } = await supabaseAdmin.rpc('criar_pre_reserva', {
      p_empresa_id: empresa_id,
      p_cliente_id: cliente_id,
      p_itens: itens,
      p_idempotencia_key: idempotencia_key,
    })

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 400 }
      )
    }

    return NextResponse.json(data)
  } catch (err) {
    console.error('Erro na pré-reserva:', err)
    return NextResponse.json(
      { error: 'Erro interno no servidor' },
      { status: 500 }
    )
  }
}
