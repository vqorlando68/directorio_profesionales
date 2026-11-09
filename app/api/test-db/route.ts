import { NextResponse } from 'next/server';
import oracledb from 'oracledb';
import { getDbConnection, getOracleConfig } from '../../../lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  const startTime = Date.now();
  const config = getOracleConfig();
  const maskedPassword =
    config.password.length > 4
      ? `${config.password.slice(0, 3)}${'*'.repeat(Math.max(4, config.password.length - 6))}${config.password.slice(-3)}`
      : '****';

  let connection: any = null;
  try {
    connection = await getDbConnection();
    const connectLatencyMs = Date.now() - startTime;

    const queryStart = Date.now();
    const infoResult = await connection.execute(
      `SELECT USER AS usuario_actual,
              SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
              SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name,
              SYS_CONTEXT('USERENV', 'INSTANCE_NAME') AS instance_name,
              SYS_CONTEXT('USERENV', 'SERVER_HOST') AS server_host,
              SYS_CONTEXT('USERENV', 'SESSIONID') AS session_id,
              TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS') AS fecha_servidor
         FROM DUAL`,
      [],
      { outFormat: oracledb.OUT_FORMAT_OBJECT }
    );

    const objetosResult = await connection.execute(
      `SELECT object_name,
              object_type,
              status,
              TO_CHAR(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') AS last_ddl
         FROM user_objects
        WHERE object_name IN (
                'PKGLN_DIRECTORIO_PROFESIONALES',
                'PKGCN_DIRECTORIO_PROFESIONALES',
                'PKGCA_TKR_DISPONIBILIDAD_BITMAP',
                'PKGTKR_DISPONIBILIDAD_BITMAP_DAO',
                'TKR_DISPONIBILIDAD_BITMAP'
              )
        ORDER BY object_name ASC, object_type ASC`,
      [],
      { outFormat: oracledb.OUT_FORMAT_OBJECT }
    );

    let totalBitmaps = 0;
    try {
      const countRes = await connection.execute(
        `SELECT COUNT(1) AS total FROM tkr_disponibilidad_bitmap`,
        [],
        { outFormat: oracledb.OUT_FORMAT_OBJECT }
      );
      totalBitmaps = countRes.rows?.[0]?.TOTAL ?? 0;
    } catch {
      totalBitmaps = -1;
    }

    const totalLatencyMs = Date.now() - startTime;
    const queryLatencyMs = Date.now() - queryStart;
    const row = infoResult.rows?.[0] || {};

    return NextResponse.json({
      conectado: true,
      mensaje: 'Conexión a Oracle Database establecida exitosamente.',
      latencia_conexion_ms: connectLatencyMs,
      latencia_consulta_ms: queryLatencyMs,
      latencia_total_ms: totalLatencyMs,
      configuracion: {
        user: config.user,
        password_masked: maskedPassword,
        connectString: config.connectString,
        modo_driver: oracledb.thin ? 'Thin (Pure JS)' : 'Thick'
      },
      sesion: {
        usuario_actual: row.USUARIO_ACTUAL || config.user,
        db_name: row.DB_NAME || '-',
        con_name: row.CON_NAME || '-',
        instance_name: row.INSTANCE_NAME || '-',
        server_host: row.SERVER_HOST || '-',
        session_id: row.SESSION_ID || '-',
        fecha_servidor: row.FECHA_SERVIDOR || '-'
      },
      total_registros_bitmap: totalBitmaps,
      objetos_bd: (objetosResult.rows || []).map((obj: any) => ({
        nombre: obj.OBJECT_NAME,
        tipo: obj.OBJECT_TYPE,
        estado: obj.STATUS,
        ultima_compilacion: obj.LAST_DDL
      }))
    });
  } catch (error: any) {
    const totalLatencyMs = Date.now() - startTime;
    return NextResponse.json(
      {
        conectado: false,
        mensaje: error?.message || 'Error al intentar conectar a Oracle Database.',
        codigo_oracle: error?.errorNum || error?.code || 'DESCONOCIDO',
        latencia_total_ms: totalLatencyMs,
        configuracion: {
          user: config.user,
          password_masked: maskedPassword,
          connectString: config.connectString,
          modo_driver: oracledb.thin ? 'Thin (Pure JS)' : 'Thick'
        }
      },
      { status: 200 }
    );
  } finally {
    if (connection) {
      try {
        await connection.close();
      } catch (closeErr) {
        console.error('Error al cerrar conexión de prueba Oracle:', closeErr);
      }
    }
  }
}

