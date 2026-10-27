import { NextRequest, NextResponse } from 'next/server';
import { executePlsqlJson, getDbConnection } from '@/lib/db';
import oracledb from 'oracledb';

export const dynamic = 'force-dynamic';

async function consultarSinDisponibilidadCore(params: {
  fecha_inicio: string;
  fecha_fin: string;
  id_convenio?: number | null;
  id_tipo_aseguramiento?: number | null;
  modalidad?: string | null;
  id_especialidad?: number | null;
}) {
  const {
    fecha_inicio,
    fecha_fin,
    id_convenio = null,
    id_tipo_aseguramiento = 1,
    modalidad = 'V',
    id_especialidad = null
  } = params;

  // 1. Intentar llamar al procedimiento PL/SQL en BD si ya fue compilado
  try {
    const resultado = await executePlsqlJson(
      'pkgln_directorio_profesionales.p_consultar_sin_disponibilidad',
      {
        fecha_inicio,
        fecha_fin,
        id_convenio,
        id_tipo_aseguramiento,
        modalidad,
        id_especialidad
      }
    );
    if (resultado && resultado.codigo === 0 && resultado.especialidades && resultado.especialidades.length > 0) {
      return resultado;
    }
  } catch (dbErr: any) {
    console.warn('Aviso: Ejecutando evaluacion directa de especialidades sin disponibilidad:', dbErr.message);
  }

  // 2. Consulta y evaluación directa contra la base de datos Oracle
  const conn = await getDbConnection();

  try {
    // A. Obtener todas las especialidades activas del sistema
    let sqlEsp = `
      SELECT e.id AS id_especialidad, e.nombre_especialidad
      FROM tkr_especialidades e
      WHERE 1 = 1
    `;
    const bindsEsp: any = {};
    if (id_especialidad) {
      sqlEsp += ` AND e.id = :id_especialidad`;
      bindsEsp.id_especialidad = id_especialidad;
    }
    sqlEsp += ` ORDER BY e.nombre_especialidad ASC`;

    const resEsp = await conn.execute(sqlEsp, bindsEsp, { outFormat: oracledb.OUT_FORMAT_OBJECT });
    const listaEspecialidades = (resEsp.rows || []) as Array<{ ID_ESPECIALIDAD: number; NOMBRE_ESPECIALIDAD: string }>;

    // B. Obtener médicos activos del directorio con sus especialidades asignadas
    const sqlMedicos = `
      SELECT u.id AS id_usuario,
             TRIM(u.nombres || ' ' || u.apellidos) AS nombre_completo,
             u.correo_electronico AS correo,
             u.telefono,
             eu.id_especialidad,
             e.nombre_especialidad,
             u.trabaja_festivos
      FROM tkr_usuarios u
      JOIN tkr_especialidades_usuario eu ON eu.id_usuario = u.id
      JOIN tkr_especialidades e ON e.id = eu.id_especialidad
      WHERE u.estado = 'A'
        AND NVL(u.ocultar_directorio, 'N') = 'N'
      ORDER BY e.nombre_especialidad, u.nombres
    `;
    const resMed = await conn.execute(sqlMedicos, {}, { outFormat: oracledb.OUT_FORMAT_OBJECT });
    const medicosRows = (resMed.rows || []) as any[];

    // Agrupar médicos por ID de especialidad
    const medicosPorEsp: Record<number, any[]> = {};
    const medicosUnicosMap: Record<number, any> = {};

    medicosRows.forEach((m) => {
      if (!medicosPorEsp[m.ID_ESPECIALIDAD]) {
        medicosPorEsp[m.ID_ESPECIALIDAD] = [];
      }
      medicosPorEsp[m.ID_ESPECIALIDAD].push(m);
      if (!medicosUnicosMap[m.ID_USUARIO]) {
        medicosUnicosMap[m.ID_USUARIO] = m;
      }
    });

    // C. Evaluar días de servicio agrupados de los médicos
    const sqlHorarios = `
      SELECT id_usuario, dia_semana
      FROM tkr_horarios_profesional
      WHERE id_usuario IN (
        SELECT u.id FROM tkr_usuarios u WHERE u.estado = 'A' AND NVL(u.ocultar_directorio, 'N') = 'N'
      )
      GROUP BY id_usuario, dia_semana
    `;
    const resHorarios = await conn.execute(sqlHorarios, {}, { outFormat: oracledb.OUT_FORMAT_OBJECT });
    const diasPorUsuario: Record<number, string[]> = {};
    (resHorarios.rows as any[] || []).forEach((h) => {
      if (!diasPorUsuario[h.ID_USUARIO]) {
        diasPorUsuario[h.ID_USUARIO] = [];
      }
      diasPorUsuario[h.ID_USUARIO].push(h.DIA_SEMANA);
    });

    // Evaluar slots para cada médico único
    const medicosEvaluadosMap: Record<number, {
      total_slots: number;
      days_of_service: string[];
    }> = {};

    const medicosIds = Object.keys(medicosUnicosMap).map(Number);
    for (const idMed of medicosIds) {
      try {
        const dispResult: any = await executePlsqlJson(
          'pkgln_directorio_profesionales.p_consultar_disponibilidad',
          {
            id_usuario: idMed,
            tipo_vista: 'RANGO',
            fecha_inicio,
            fecha_fin,
            id_convenio: id_convenio || null,
            id_tipo_aseguramiento: id_tipo_aseguramiento || 1,
            modalidad: modalidad || 'V'
          }
        );
        const slotsCount = Number(dispResult?.total_slots_rango ?? dispResult?.total_slots ?? 0);
        medicosEvaluadosMap[idMed] = {
          total_slots: slotsCount,
          days_of_service: diasPorUsuario[idMed] || []
        };
      } catch {
        medicosEvaluadosMap[idMed] = {
          total_slots: 0,
          days_of_service: diasPorUsuario[idMed] || []
        };
      }
    }

    // D. Construir el reporte jerárquico por Especialidad
    const especialidadesResultado: any[] = [];
    let totalEspecialidadesSinMedicos = 0;
    let totalMedicosSinCupos = 0;

    for (const esp of listaEspecialidades) {
      const idEsp = esp.ID_ESPECIALIDAD;
      const nombreEsp = esp.NOMBRE_ESPECIALIDAD;
      const medicosDeEstaEsp = medicosPorEsp[idEsp] || [];

      if (medicosDeEstaEsp.length === 0) {
        // Caso 1: Especialidad sin ningún médico asignado
        totalEspecialidadesSinMedicos++;
        especialidadesResultado.push({
          id_especialidad: idEsp,
          nombre_especialidad: nombreEsp,
          tiene_profesionales: false,
          tipo: 'SIN_PROFESIONALES',
          total_profesionales: 0,
          profesionales: []
        });
      } else {
        // Caso 2: Especialidad con médicos -> verificar cuáles tienen 0 cupos
        const medicosSinDisponibilidad = medicosDeEstaEsp.filter((med) => {
          const evalMed = medicosEvaluadosMap[med.ID_USUARIO];
          return (evalMed?.total_slots ?? 0) === 0;
        });

        if (medicosSinDisponibilidad.length > 0) {
          totalMedicosSinCupos += medicosSinDisponibilidad.length;
          especialidadesResultado.push({
            id_especialidad: idEsp,
            nombre_especialidad: nombreEsp,
            tiene_profesionales: true,
            tipo: 'CON_PROFESIONALES_SIN_DISPONIBILIDAD',
            total_profesionales: medicosSinDisponibilidad.length,
            profesionales: medicosSinDisponibilidad.map((m) => {
              const evalMed = medicosEvaluadosMap[m.ID_USUARIO];
              return {
                id_usuario: m.ID_USUARIO,
                nombre_completo: m.NOMBRE_COMPLETO,
                correo: m.CORREO || '',
                telefono: m.TELEFONO || '',
                days_of_service: evalMed?.days_of_service || [],
                motivo: (evalMed?.days_of_service || []).length === 0
                  ? 'Sin horarios configurados en el rango de fechas'
                  : 'Horarios configurados (' + evalMed.days_of_service.join(', ') + ') pero sin cupos libres en el rango'
              };
            })
          });
        }
      }
    }

    return {
      codigo: 0,
      mensaje: 'Especialidades y profesionales sin disponibilidad recuperados exitosamente',
      fecha_inicio,
      fecha_fin,
      total_sin_disponibilidad: especialidadesResultado.length,
      total_especialidades_sin_medicos: totalEspecialidadesSinMedicos,
      total_medicos_sin_cupos: totalMedicosSinCupos,
      especialidades: especialidadesResultado
    };
  } finally {
    await conn.close();
  }
}

// Handler GET
export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const fecha_inicio = searchParams.get('fecha_inicio') || new Date().toISOString().split('T')[0];
    const fecha_fin = searchParams.get('fecha_fin') || fecha_inicio;
    const id_convenio = searchParams.get('id_convenio') ? Number(searchParams.get('id_convenio')) : null;
    const id_tipo_aseguramiento = searchParams.get('id_tipo_aseguramiento')
      ? Number(searchParams.get('id_tipo_aseguramiento'))
      : 1;
    const modalidad = searchParams.get('modalidad') || 'V';
    const id_especialidad = searchParams.get('id_especialidad')
      ? Number(searchParams.get('id_especialidad'))
      : null;

    const res = await consultarSinDisponibilidadCore({
      fecha_inicio,
      fecha_fin,
      id_convenio,
      id_tipo_aseguramiento,
      modalidad,
      id_especialidad
    });

    return NextResponse.json(res);
  } catch (err: any) {
    console.error('Error en GET /api/sin-disponibilidad:', err);
    return NextResponse.json(
      {
        codigo: -20000,
        mensaje: err.message || 'Error interno al consultar sin disponibilidad'
      },
      { status: 500 }
    );
  }
}

// Handler POST
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const res = await consultarSinDisponibilidadCore(body);
    return NextResponse.json(res);
  } catch (err: any) {
    console.error('Error en POST /api/sin-disponibilidad:', err);
    return NextResponse.json(
      {
        codigo: -20000,
        mensaje: err.message || 'Error interno al consultar sin disponibilidad'
      },
      { status: 500 }
    );
  }
}
