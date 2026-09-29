import { redirect } from 'next/navigation'

// App interno: a entrada é o painel (o middleware manda para o login quem não entrou)
export default function HomePage() {
  redirect('/dashboard')
}
