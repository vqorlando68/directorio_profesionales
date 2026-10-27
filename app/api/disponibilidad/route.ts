import { NextRequest, NextResponse } from 'next/server';
import { executePlsqlJson } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    // Consulta de disponibilidad para rango de fechas
    if (body.tipo_vista === 'RANGO' && body.fecha_inicio && body.fecha_fin) {
      // 1. Intentar consulta atómica directa en Oracle mediante PKGLN (ultrarrápida en 1 solo viaje)
      try {
        const resPlsql = await executePlsqlJson(
          'pkgln_directorio_profesionales.p_consultar_disponibilidad',
          body
        );

        if (resPlsql && resPlsql.codigo === 0 && Array.isArray(resPlsql.dias_disponibles)) {
          return NextResponse.json(resPlsql);
        }
      } catch (errPlsql: any) {
        console.warn('Fallback a iteración de fechas en API route:', errPlsql?.message);
      }

      // 2. Fallback de iteración: admite hasta 365 días (1 año completo)
      const [y1, m1, d1] = body.fecha_inicio.split('-').map(Number);
      const [y2, m2, d2] = body.fecha_fin.split('-').map(Number);
      const fInicio = new Date(y1, m1 - 1, d1);
      const fFin = new Date(y2, m2 - 1, d2);

      const fechasRango: string[] = [];
      const actual = new Date(fInicio);
      let contador = 0;

      while (actual <= fFin && contador < 365) {
        const y = actual.getFullYear();
        const m = String(actual.getMonth() + 1).padStart(2, '0');
        const d = String(actual.getDate()).padStart(2, '0');
        fechasRango.push(`${y}-${m}-${d}`);
        actual.setDate(actual.getDate() + 1);
        contador++;
      }

      // Ejecución concurrente en bloques controlados para no saturar conexiones
      const diasConsultados: any[] = [];
      const batchSize = 10;
      for (let i = 0; i < fechasRango.length; i += batchSize) {
        const batch = fechasRango.slice(i, i + batchSize);
        const batchResults = await Promise.all(
          batch.map(async (fechaIso) => {
            const payloadDia = {
              id_usuario: body.id_usuario,
              fecha: fechaIso,
              tipo_vista: 'DIA',
              id_convenio: body.id_convenio || null,
              id_tipo_aseguramiento: body.id_tipo_aseguramiento || 1,
              modalidad: body.modalidad || 'V'
            };

            try {
              const resDia = await executePlsqlJson(
                'pkgln_directorio_profesionales.p_consultar_disponibilidad',
                payloadDia
              );

              if (resDia && resDia.codigo === 0) {
                return resDia;
              } else {
                return {
                  fecha: fechaIso,
                  total_slots: 0,
                  slots: [],
                  tipo_horario_aplica: 'NINGUNO',
                  mensaje: resDia?.mensaje || 'Sin disponibilidad'
                };
              }
            } catch (e: any) {
              return {
                fecha: fechaIso,
                total_slots: 0,
                slots: [],
                tipo_horario_aplica: 'ERROR',
                mensaje: e.message || 'Error al consultar fecha'
              };
            }
          })
        );
        diasConsultados.push(...batchResults);
      }

      // Filtrar solo los días con disponibilidad activa
      const diasConDisponibilidad = diasConsultados.filter(
        (d) => d.total_slots > 0 && d.slots && d.slots.length > 0
      );

      const totalSlotsRango = diasConDisponibilidad.reduce(
        (acc, d) => acc + (d.total_slots || 0),
        0
      );

      return NextResponse.json({
        codigo: 0,
        mensaje: 'Rango consultado exitosamente',
        id_usuario: body.id_usuario,
        fecha_inicio: body.fecha_inicio,
        fecha_fin: body.fecha_fin,
        total_slots_rango: totalSlotsRango,
        dias_disponibles: diasConDisponibilidad,
        todos_los_dias: diasConsultados
      });
    }

    // Consulta estándar para un día específico
    const resultado = await executePlsqlJson(
      'pkgln_directorio_profesionales.p_consultar_disponibilidad',
      body
    );
    return NextResponse.json(resultado);
  } catch (err: any) {
    console.error('Error en /api/disponibilidad:', err);
    return NextResponse.json(
      {
        codigo: -20000,
        mensaje: err.message || 'Error interno al consultar disponibilidad'
      },
      { status: 500 }
    );
  }
}
