import { NextRequest, NextResponse } from 'next/server';
import { executePlsqlJson } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const resultado = await executePlsqlJson(
      'pkgln_directorio_profesionales.p_consultar_directorio',
      body
    );
    return NextResponse.json(resultado);
  } catch (err: any) {
    console.error('Error en /api/directorio:', err);
    return NextResponse.json(
      {
        codigo: -20000,
        mensaje: err.message || 'Error interno al consultar directorio de profesionales'
      },
      { status: 500 }
    );
  }
}
