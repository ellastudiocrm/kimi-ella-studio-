import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(
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

  const [profissionalResult, servicosResult, fotosResult] = await Promise.all([
    supabase
      .from('profissionais')
      .select('id, nome, foto_url, bio, especialidades, ativo')
      .eq('id', params.id)
      .single(),
    supabase
      .from('profissional_servicos')
      .select('servico_id')
      .eq('profissional_id', params.id),
    supabase
      .from('profissional_fotos')
      .select('id, url, ordem')
      .eq('profissional_id', params.id)
      .order('ordem'),
  ])

  if (profissionalResult.error) {
    console.error('Erro ao carregar profissional:', profissionalResult.error)
    return NextResponse.json({ error: profissionalResult.error.message }, { status: 500 })
  }

  return NextResponse.json({
    ...profissionalResult.data,
    servicos: (servicosResult.data ?? []).map((s) => s.servico_id),
    fotos: fotosResult.data ?? [],
  })
}

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
  const { nome, bio, especialidades, ativo, servicos } = body

  const update: Record<string, unknown> = {}
  if (nome !== undefined) update.nome = nome
  if (bio !== undefined) update.bio = bio
  if (especialidades !== undefined) update.especialidades = especialidades
  if (ativo !== undefined) update.ativo = ativo

  if (Object.keys(update).length > 0) {
    const { error } = await supabase
      .from('profissionais')
      .update(update)
      .eq('id', params.id)

    if (error) {
      console.error('Erro ao atualizar profissional:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }
  }

  // Atualiza associação de serviços
  if (Array.isArray(servicos)) {
    const { data: existentes } = await supabase
      .from('profissional_servicos')
      .select('servico_id')
      .eq('profissional_id', params.id)

    const existentesIds = new Set((existentes ?? []).map((s) => s.servico_id))
    const novosIds = new Set(servicos)

    const aRemover = Array.from(existentesIds).filter((id) => !novosIds.has(id))
    const aAdicionar = Array.from(novosIds).filter((id) => !existentesIds.has(id))

    if (aRemover.length > 0) {
      const { error } = await supabase
        .from('profissional_servicos')
        .delete()
        .eq('profissional_id', params.id)
        .in('servico_id', aRemover)

      if (error) {
        console.error('Erro ao remover serviços:', error)
        return NextResponse.json({ error: error.message }, { status: 500 })
      }
    }

    if (aAdicionar.length > 0) {
      const { data: usuario } = await supabase
        .from('usuarios_internos')
        .select('empresa_id')
        .eq('auth_user_id', user.id)
        .single()

      const empresaId = usuario?.empresa_id
      const rows = aAdicionar.map((servicoId) => ({
        profissional_id: params.id,
        servico_id: servicoId,
        empresa_id: empresaId,
      }))

      const { error } = await supabase.from('profissional_servicos').insert(rows)

      if (error) {
        console.error('Erro ao adicionar serviços:', error)
        return NextResponse.json({ error: error.message }, { status: 500 })
      }
    }
  }

  return NextResponse.json({ ok: true })
}
