import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
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
    const profissionalId = formData.get('profissionalId') as string | null

    if (!file || !profissionalId) {
      return NextResponse.json({ error: 'Ficheiro e ID do profissional obrigatórios' }, { status: 400 })
    }

    if (!file.type.startsWith('image/')) {
      return NextResponse.json({ error: 'Só são permitidas imagens' }, { status: 400 })
    }

    if (file.size > 5 * 1024 * 1024) {
      return NextResponse.json({ error: 'Máximo 5MB' }, { status: 400 })
    }

    const ext = file.name.split('.').pop() ?? 'jpg'
    const path = `${usuario.empresa_id}/${profissionalId}/${Date.now()}.${ext}`

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

    return NextResponse.json({ url: publicUrl })
  } catch (err) {
    console.error('Erro no upload:', err)
    return NextResponse.json({ error: 'Erro interno' }, { status: 500 })
  }
}
