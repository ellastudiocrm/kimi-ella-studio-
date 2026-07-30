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

  const { data: profissionais, error } = await supabase
    .from('profissionais')
    .select('id, nome, foto_url, bio, especialidades, ativo')
    .order('nome')

  if (error) {
    console.error('Erro ao carregar profissionais:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json(profissionais)
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

  const { data: usuario, error: usuarioError } = await supabase
    .from('usuarios_internos')
    .select('empresa_id, perfil')
    .eq('auth_user_id', user.id)
    .single()

  if (usuarioError || !usuario || !['admin', 'gestor'].includes(usuario.perfil)) {
    return NextResponse.json({ error: 'Sem permissão' }, { status: 403 })
  }

  const body = await request.json()
  const { nome } = body

  if (!nome || typeof nome !== 'string') {
    return NextResponse.json({ error: 'Nome obrigatório' }, { status: 400 })
  }

  const { data: profissional, error: insertError } = await supabase
    .from('profissionais')
    .insert({
      empresa_id: usuario.empresa_id,
      nome,
      ativo: true,
    })
    .select('id')
    .single()

  if (insertError || !profissional) {
    console.error('Erro ao criar profissional:', insertError)
    return NextResponse.json({ error: insertError?.message || 'Erro ao criar profissional' }, { status: 500 })
  }

  return NextResponse.json({ id: profissional.id }, { status: 201 })
}
