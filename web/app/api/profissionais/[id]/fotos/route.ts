import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

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

  const { data: fotos, error } = await supabase
    .from('profissional_fotos')
    .select('id, url, ordem')
    .eq('profissional_id', params.id)
    .order('ordem')

  if (error) {
    console.error('Erro ao carregar fotos:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json(fotos ?? [])
}

export async function POST(
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

  const { data: usuario, error: perfilError } = await supabase
    .from('usuarios_internos')
    .select('perfil, empresa_id')
    .eq('auth_user_id', user.id)
    .single()

  if (perfilError || !usuario || !['admin', 'gestor'].includes(usuario.perfil)) {
    return NextResponse.json({ error: 'Sem permissão' }, { status: 403 })
  }

  try {
    const formData = await request.formData()
    const file = formData.get('file') as File | null

    if (!file) {
      return NextResponse.json({ error: 'Ficheiro obrigatório' }, { status: 400 })
    }

    if (!file.type.startsWith('image/')) {
      return NextResponse.json({ error: 'Só são permitidas imagens' }, { status: 400 })
    }

    if (file.size > 5 * 1024 * 1024) {
      return NextResponse.json({ error: 'Máximo 5MB' }, { status: 400 })
    }

    const ext = file.name.split('.').pop() ?? 'jpg'
    const path = `${usuario.empresa_id}/${params.id}/galeria/${Date.now()}.${ext}`

    const admin = createAdminClient()
    const { error: uploadError } = await admin.storage
      .from('profissionais')
      .upload(path, file, {
        cacheControl: '3600',
        upsert: true,
      })

    if (uploadError) {
      console.error('Erro no upload:', uploadError)
      return NextResponse.json({ error: uploadError.message }, { status: 500 })
    }

    const {
      data: { publicUrl },
    } = admin.storage.from('profissionais').getPublicUrl(path)

    // Determina próxima ordem
    const { data: existentes } = await supabase
      .from('profissional_fotos')
      .select('ordem')
      .eq('profissional_id', params.id)
      .order('ordem', { ascending: false })
      .limit(1)

    const ordem = (existentes?.[0]?.ordem ?? 0) + 1

    const { data: foto, error: insertError } = await supabase
      .from('profissional_fotos')
      .insert({
        profissional_id: params.id,
        url: publicUrl,
        ordem,
      })
      .select('id, url, ordem')
      .single()

    if (insertError || !foto) {
      console.error('Erro ao registar foto:', insertError)
      return NextResponse.json({ error: insertError?.message || 'Erro ao registar foto' }, { status: 500 })
    }

    return NextResponse.json(foto, { status: 201 })
  } catch (err) {
    console.error('Erro no upload:', err)
    return NextResponse.json({ error: 'Erro interno' }, { status: 500 })
  }
}
