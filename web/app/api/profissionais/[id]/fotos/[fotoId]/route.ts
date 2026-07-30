import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function DELETE(
  request: Request,
  { params }: { params: { id: string; fotoId: string } }
) {
  const supabase = createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    return NextResponse.json({ error: 'Não autenticado' }, { status: 401 })
  }

  const { data: usuario, error: perfilError } = await supabase
    .from('usuarios_internos')
    .select('perfil')
    .eq('auth_user_id', user.id)
    .single()

  if (perfilError || !usuario || !['admin', 'gestor'].includes(usuario.perfil)) {
    return NextResponse.json({ error: 'Sem permissão' }, { status: 403 })
  }

  const { error } = await supabase
    .from('profissional_fotos')
    .delete()
    .eq('id', params.fotoId)
    .eq('profissional_id', params.id)

  if (error) {
    console.error('Erro ao remover foto:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ ok: true })
}
