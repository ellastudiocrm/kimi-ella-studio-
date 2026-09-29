// Dados fixos da marca e utilitários de formatação.

export type Cardapio = 'ella_studio' | 'ella_men'

export const CONTATO = {
  whatsapp: '5519996039414',
  telefoneExibicao: '(19) 99603-9414',
  endereco: 'R. Antônio Cremasco, 338 - Sala 2',
  bairro: 'Santa Gertrudes, Valinhos - SP',
  mapa: 'https://www.google.com/maps/search/?api=1&query=ELLA+Studio+Valinhos',
  instagram: 'https://www.instagram.com/ellastudioblz/',
  instagramUser: '@ellastudioblz',
  horarios: ['Ter a Sex · 9h às 17h', 'Sáb · 8h às 13h'],
  siteOficial: 'https://www.ellastudioblz.com.br',
}

export function linkWhatsApp(texto?: string) {
  const base = `https://wa.me/${CONTATO.whatsapp}`
  return texto ? `${base}?text=${encodeURIComponent(texto)}` : base
}

export const CARDAPIOS: Record<
  Cardapio,
  { nome: string; publico: string; titulo: string; descricao: string; hero: string }
> = {
  ella_studio: {
    nome: 'ELLA Studio',
    publico: 'Para ela',
    titulo: 'Escolha o cuidado que combina com o seu momento',
    descricao:
      'Unhas, cílios, sobrancelhas, depilação, massagens e limpeza de pele em um espaço pensado para realçar a sua beleza.',
    hero: '/marca/hero-studio.webp',
  },
  ella_men: {
    nome: 'ELLA MEN',
    publico: 'Para ele',
    titulo: 'Cuidado masculino também é cuidado pessoal',
    descricao:
      'Limpeza de pele, sobrancelhas, mãos e pés, depilação e massagens com atendimento discreto e personalizado.',
    hero: '/marca/hero-men.webp',
  },
}

export function cardapioValido(valor: string | null | undefined): Cardapio {
  return valor === 'ella_men' ? 'ella_men' : 'ella_studio'
}

// Foto de cada serviço (fotos do site oficial). A foto cadastrada no
// backoffice (servicos.foto_url) tem prioridade.
const FOTOS_STUDIO: [RegExp, string][] = [
  [/cilios/, 'cilios'],
  [/sobrancelha/, 'sobrancelhas'],
  [/limpeza/, 'limpeza'],
  [/drenagem/, 'drenagem'],
  [/modeladora/, 'modeladora'],
  [/massagem/, 'relaxante'],
  [/depilacao|epilacao/, 'depilacao'],
  [/pedicure|pes/, 'pedicure'],
  [/manicure|unha/, 'manicure'],
]

const FOTOS_MEN: [RegExp, string][] = [
  [/sobrancelha/, 'sobrancelhas'],
  [/limpeza/, 'limpeza'],
  [/terapeutica/, 'terapeutica'],
  [/modeladora/, 'modeladora'],
  [/massagem/, 'relaxante'],
  [/depilacao|epilacao/, 'depilacao'],
  [/pedicure|pes/, 'pedicure'],
  [/manicure|unha/, 'manicure'],
]

export function fotoServico(nomeTecnico: string, cardapio: Cardapio, fotoUrl?: string | null) {
  if (fotoUrl) return fotoUrl
  if (cardapio === 'ella_men') {
    const achado = FOTOS_MEN.find(([re]) => re.test(nomeTecnico))
    return `/marca/men/${achado ? achado[1] : 'limpeza'}.png`
  }
  const achado = FOTOS_STUDIO.find(([re]) => re.test(nomeTecnico))
  return achado ? `/marca/studio/${achado[1]}.webp` : '/marca/card-studio.webp'
}

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })

export function formatarPreco(valor: number | string | null | undefined) {
  return moeda.format(Number(valor ?? 0))
}

export function formatarDuracao(minutos: number) {
  if (minutos < 60) return `${minutos} min`
  const h = Math.floor(minutos / 60)
  const m = minutos % 60
  return m ? `${h}h${String(m).padStart(2, '0')}` : `${h}h`
}

// O negócio funciona no fuso de São Paulo, independentemente do fuso do aparelho.
export const FUSO = 'America/Sao_Paulo'

export function hojeSaoPaulo() {
  // en-CA formata como AAAA-MM-DD
  return new Intl.DateTimeFormat('en-CA', { timeZone: FUSO }).format(new Date())
}

export function formatarHora(iso: string) {
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: FUSO,
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
}

// Recebe 'AAAA-MM-DD' e formata sem risco de "voltar um dia" por causa do fuso.
export function formatarDataLonga(dataISO: string) {
  const [a, m, d] = dataISO.split('-').map(Number)
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: 'UTC',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(new Date(Date.UTC(a, m - 1, d, 12)))
}

// Minutos desde a meia-noite (horário de São Paulo)
export function minutosDoDia(iso: string) {
  const [h, m] = formatarHora(iso).split(':').map(Number)
  return h * 60 + m
}

// Soma dias a uma data 'AAAA-MM-DD'
export function somarDias(dataISO: string, dias: number) {
  const [a, m, d] = dataISO.split('-').map(Number)
  return new Date(Date.UTC(a, m - 1, d + dias)).toISOString().slice(0, 10)
}

export function diaDaSemanaISO(dataISO: string) {
  const [a, m, d] = dataISO.split('-').map(Number)
  return new Date(Date.UTC(a, m - 1, d)).getUTCDay()
}

export function formatarDataCurta(dataISO: string) {
  const [a, m, d] = dataISO.split('-').map(Number)
  return new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC', weekday: 'short', day: 'numeric' })
    .format(new Date(Date.UTC(a, m - 1, d, 12)))
    .replace('.', '')
}

export function dataDoSlot(iso: string) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: FUSO }).format(new Date(iso))
}
