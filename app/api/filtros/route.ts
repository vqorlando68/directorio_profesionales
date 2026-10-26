import { NextRequest, NextResponse } from 'next/server';
import { executePlsqlJson } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const resultado = await executePlsqlJson(
      'pkgln_directorio_profesionales.p_consultar_filtros',
      {}
    );
    return NextResponse.json(resultado);
  } catch (err: any) {
    console.error('Error en /api/filtros:', err);
    return NextResponse.json(
      {
        codigo: -20000,
        mensaje: err.message || 'Error al consultar catálogo de filtros'
      },
      { status: 500 }
    );
  }
}
